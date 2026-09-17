// ABI for contracts/src/TownNoticeBoard.sol
export const townNoticeBoardAbi = [
  {
    type: 'function',
    name: 'post',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'text', type: 'string' }],
    outputs: [{ name: 'id', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'count',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'get',
    stateMutability: 'view',
    inputs: [{ name: 'id', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'author', type: 'address' },
          { name: 'postedAt', type: 'uint64' },
          { name: 'text', type: 'string' },
        ],
      },
    ],
  },
  {
    type: 'event',
    name: 'NoticePosted',
    inputs: [
      { name: 'id', type: 'uint256', indexed: true },
      { name: 'author', type: 'address', indexed: true },
      { name: 'text', type: 'string', indexed: false },
    ],
  },
  { type: 'error', name: 'EmptyNotice', inputs: [] },
  {
    type: 'error',
    name: 'NoticeTooLong',
    inputs: [
      { name: 'length', type: 'uint256' },
      { name: 'max', type: 'uint256' },
    ],
  },
];
