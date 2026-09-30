import { BaseError, ContractFunctionRevertedError, parseEventLogs } from 'viem';
import { publicClient } from './chain.js';
import { emitRefresh } from './refresh.js';

/** Turns a viem error into one sentence a student can act on. */
export function explainError(e) {
  if (e instanceof BaseError) {
    const reverted = e.walk((x) => x instanceof ContractFunctionRevertedError);
    if (reverted?.data?.errorName) {
      const args = reverted.data.args?.length ? ` (${reverted.data.args.join(', ')})` : '';
      return `The contract refused it: ${reverted.data.errorName}${args}`;
    }
    if (e.shortMessage?.includes('User rejected')) return 'You rejected the request in MetaMask.';
    return e.shortMessage || e.message;
  }
  return e?.message || String(e);
}

/**
 * Simulate → estimate → sign → wait → decode, reporting each stage through setTx.
 * Simulating first means a doomed transaction never reaches MetaMask.
 *
 * The gas limit goes out with 25% headroom. An estimate is made against the chain as it
 * stands NOW, but the transaction runs in the next block, and several of the town's
 * contracts cost more once time has passed (a loan accrues interest, a storage slot that
 * was just written gets rewritten). Found in rehearsal: a borrow estimated one block after
 * its collateral deposit ran out of gas inside the passport stamp and reverted. MetaMask
 * adds its own buffer, other wallets may not, and unused gas is never charged.
 */
export async function runTx({ wallet, address, abi, functionName, args = [], setTx, onDone }) {
  setTx({ status: 'pending' });
  try {
    const { request } = await publicClient.simulateContract({
      address,
      abi,
      functionName,
      args,
      account: wallet.account,
    });
    const estimate = await publicClient.estimateContractGas({ ...request, account: wallet.account });
    const hash = await wallet.walletClient.writeContract({ ...request, gas: (estimate * 125n) / 100n });
    setTx({ hash, status: 'pending' });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const events = parseEventLogs({ abi, logs: receipt.logs });
    if (receipt.status !== 'success') {
      // It passed simulation, so something changed between the check and the block: another
      // transaction got there first, or it ran out of gas. Nothing happened but the fee.
      setTx({
        hash,
        status: receipt.status,
        receipt,
        events,
        error:
          'Included in a block but reverted: nothing changed except the fee. Something moved between the check and the block (or it ran out of gas). Try again.',
      });
      emitRefresh();
      return null;
    }
    setTx({ hash, status: receipt.status, receipt, events });
    await onDone?.(receipt);
    emitRefresh();
    return receipt;
  } catch (e) {
    setTx((t) => ({ ...(t || {}), status: 'error', error: explainError(e) }));
    return null;
  }
}
