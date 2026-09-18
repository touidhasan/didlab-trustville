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
 * Simulate → sign → wait → decode, reporting each stage through setTx.
 * Simulating first means a doomed transaction never reaches MetaMask.
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
    const hash = await wallet.walletClient.writeContract(request);
    setTx({ hash, status: 'pending' });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const events = parseEventLogs({ abi, logs: receipt.logs });
    setTx({ hash, status: receipt.status, receipt, events });
    await onDone?.(receipt);
    emitRefresh();
    return receipt;
  } catch (e) {
    setTx((t) => ({ ...(t || {}), status: 'error', error: explainError(e) }));
    return null;
  }
}
