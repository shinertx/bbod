'use client'

import { useAccount, useConnect, useDisconnect } from 'wagmi'

export function ConnectWallet() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()

  const injectedConnector = connectors.find(
    (connector) => connector.id === 'injected'
  )

  if (isConnected) {
    return (
      <div className="flex items-center space-x-4">
        <div className="text-sm">Connected: {address}</div>
        <button
          onClick={() => disconnect()}
          className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700"
        >
          Disconnect
        </button>
      </div>
    )
  }
  return (
    <button
      onClick={() => connect({ connector: injectedConnector })}
      className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
    >
      Connect Wallet
    </button>
  )
}
