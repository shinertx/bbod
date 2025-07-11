# Testnet Deployment & Integration Testing - Week 2

## Testnet Deployment Script

### 1. Environment Setup
```bash
# Configure testnet environment
cp env.example .env.testnet

# Set testnet configuration
export NETWORK=sepolia
export RPC_URL=$SEPOLIA_RPC
export PRIVATE_KEY=$TESTNET_PRIVATE_KEY
```

### 2. Deploy Contracts
```bash
# Deploy to Sepolia testnet
npm run deploy:testnet

# Verify deployments
npm run verify:testnet

# Setup initial parameters
npm run initialize:testnet
```

### 3. Bot Infrastructure Testing
```bash
# Start oracle feeders (testnet mode)
pm2 start daemon/oracleBot.ts --name oracle-testnet-1 -- --network testnet
pm2 start daemon/oracleBot.ts --name oracle-testnet-2 -- --network testnet
pm2 start daemon/oracleBot.ts --name oracle-testnet-3 -- --network testnet

# Start settlement bots
pm2 start bots/settleBot.ts --name settler-testnet -- --network testnet
pm2 start bots/commitRevealBot.ts --name threshold-testnet -- --network testnet

# Start monitoring
pm2 start daemon/monitoringAgent.ts --name monitor-testnet -- --network testnet
```

### 4. Integration Test Scenarios

#### Scenario 1: Full Option Cycle
- [ ] Create option series
- [ ] Buy options with various strikes
- [ ] Oracle price updates
- [ ] Exercise ITM options
- [ ] Withdraw margin OTM

#### Scenario 2: BSP Betting Cycle  
- [ ] Commit bets on both sides
- [ ] Reveal in time window
- [ ] Oracle settlement
- [ ] Claim payouts
- [ ] Test non-reveal forfeiture

#### Scenario 3: Threshold Management
- [ ] Commit new threshold
- [ ] Reveal threshold
- [ ] Settlement with new threshold
- [ ] Timeout scenarios

#### Scenario 4: Stress Testing
- [ ] High gas price scenarios
- [ ] Large bet amounts
- [ ] Rapid successive rounds
- [ ] Oracle feed interruptions

### 5. Frontend Integration
```bash
# Deploy testnet frontend
cd frontend
export NEXT_PUBLIC_NETWORK=testnet
export NEXT_PUBLIC_ORACLE_ADDRESS=$TESTNET_ORACLE
export NEXT_PUBLIC_BBOD_ADDRESS=$TESTNET_BBOD  
export NEXT_PUBLIC_BSP_ADDRESS=$TESTNET_BSP

npm run build
npm run deploy:testnet
```

### 6. User Acceptance Testing
- [ ] UI/UX flows work correctly
- [ ] MetaMask integration smooth
- [ ] Transaction confirmations clear
- [ ] Error handling graceful
- [ ] Performance acceptable

## Testnet Checklist
- [ ] All contracts deployed and verified
- [ ] Oracle feeds operational (3 feeders)
- [ ] Bots running with proper restart policies
- [ ] Frontend deployed and functional
- [ ] Monitoring dashboards showing health
- [ ] At least 48 hours of continuous operation
- [ ] All integration scenarios passed
- [ ] Performance metrics within targets

## Success Metrics
- Uptime: >99.5%
- Transaction success rate: >98%
- Oracle feed latency: <30 seconds
- Settlement accuracy: 100%
- Gas optimization: <20% overhead
