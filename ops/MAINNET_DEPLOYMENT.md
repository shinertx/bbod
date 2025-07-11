# Mainnet Deployment & Infrastructure Setup - Week 3

## Pre-Deployment Security

### 1. Final Security Checks
```bash
# Final audit of any changes since testnet
slither contracts/ --config slither.config.json

# Verify bytecode matches audited version
forge build --force
diff out/ audited-bytecode/

# Check for any new dependencies
npm audit --audit-level high
```

### 2. Safe Multisig Setup
```bash
# Deploy Safe with 3/5 or 2/3 configuration
npm run setup:safe:mainnet

# Test Safe functionality on testnet first
npm run test:safe:testnet

# Add signers and verify hardware wallet compatibility
npm run verify:safe:signers
```

## Mainnet Deployment Process

### 1. Contract Deployment
```bash
# Deploy via Safe multisig (requires multiple signatures)
npm run deploy:mainnet:safe

# Contracts to deploy:
# 1. BlobFeeOracle (with 3+ oracle signers)
# 2. BlobOptionDesk (linked to oracle)  
# 3. CommitRevealBSP (linked to oracle)
```

### 2. Contract Verification
```bash
# Verify all contracts on Etherscan
forge verify-contract --chain mainnet \
  --constructor-args $(cast abi-encode "constructor(address[])" "[$ORACLE_SIGNERS]") \
  $ORACLE_ADDRESS \
  contracts/BlobFeeOracle.sol:BlobFeeOracle

forge verify-contract --chain mainnet \
  --constructor-args $(cast abi-encode "constructor(address)" "$ORACLE_ADDRESS") \
  $BBOD_ADDRESS \
  contracts/BlobOptionDesk.sol:BlobOptionDesk

forge verify-contract --chain mainnet \
  --constructor-args $(cast abi-encode "constructor(address)" "$ORACLE_ADDRESS") \
  $BSP_ADDRESS \
  contracts/CommitRevealBSP.sol:CommitRevealBSP
```

### 3. Infrastructure Deployment

#### Production Server Setup
```bash
# Deploy to production infrastructure (AWS/GCP/dedicated)
# Requirements:
# - 3+ geographically distributed nodes
# - Hardware wallets for bot keys
# - 8+ ETH gas buffer in operations wallet
# - Backup & monitoring systems

# Server 1: Primary Oracle Feeder + Settlement
# Server 2: Secondary Oracle Feeder + Monitoring  
# Server 3: Tertiary Oracle Feeder + Backup
```

#### Oracle Infrastructure
```bash
# Configure 3 oracle feeders with distinct RPC endpoints
export ORACLE_1_RPC=$ALCHEMY_MAINNET
export ORACLE_2_RPC=$INFURA_MAINNET  
export ORACLE_3_RPC=$QUICKNODE_MAINNET

# Start oracle feeders
pm2 start ecosystem.config.js --only oracle-mainnet-1
pm2 start ecosystem.config.js --only oracle-mainnet-2
pm2 start ecosystem.config.js --only oracle-mainnet-3

# Configure auto-restart and logging
pm2 startup
pm2 save
```

#### Settlement Bot Infrastructure  
```bash
# Start settlement & threshold management bots
pm2 start ecosystem.config.js --only settler-mainnet
pm2 start ecosystem.config.js --only threshold-mainnet
pm2 start ecosystem.config.js --only monitor-mainnet

# Configure alerts for bot failures
pm2 install pm2-slack
```

### 4. Monitoring & Alerting Setup

#### Prometheus Configuration
```yaml
# Update prometheus/prometheus.yml for mainnet
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'bbod-mainnet'
    static_configs:
      - targets: ['localhost:3001', 'localhost:3002', 'localhost:3003']
    
  - job_name: 'ethereum-node'
    static_configs:
      - targets: ['node1:8545', 'node2:8545', 'node3:8545']
```

#### Grafana Dashboards
```bash
# Deploy production dashboards
docker-compose -f docker/docker-compose.prod.yml up -d

# Import mainnet-specific dashboards
# - Oracle feed health
# - Settlement success rates
# - Gas usage optimization
# - User activity metrics
```

#### Alert Rules
```yaml
# prometheus/alert.rules.yml - Mainnet specific
groups:
  - name: bbod.rules
    rules:
    - alert: OracleFeedDown
      expr: up{job="oracle-feeder"} == 0
      for: 2m
      annotations:
        summary: "Oracle feeder {{ $labels.instance }} is down"
        
    - alert: HighGasUsage
      expr: ethereum_gas_price_gwei > 100
      for: 5m
      annotations:
        summary: "Gas prices elevated: {{ $value }} gwei"
        
    - alert: SettlementFailed
      expr: settlement_failures_total > 0
      for: 1m
      annotations:
        summary: "Settlement failure detected"
```

### 5. Operations Wallet Setup
```bash
# Setup operations wallet with 8+ ETH
# For gas costs of:
# - Oracle feeds: ~0.5 ETH/month
# - Settlements: ~1 ETH/month  
# - Threshold updates: ~0.5 ETH/month
# - Emergency operations: ~2 ETH buffer
# - Total buffer: 8+ ETH recommended

# Configure automated top-ups if balance <2 ETH
```

## Mainnet Checklist
- [ ] Safe multisig deployed and tested (3/5 signers)
- [ ] All contracts deployed via Safe and verified
- [ ] 3+ oracle feeders operational with distinct RPCs
- [ ] Settlement bots running with restart policies
- [ ] Monitoring stack deployed (Prometheus + Grafana)
- [ ] Alert rules configured and tested
- [ ] Operations wallet funded with 8+ ETH
- [ ] Hardware wallets configured for all bot keys
- [ ] Backup & disaster recovery procedures tested
- [ ] Emergency kill-switch procedures documented

## Success Metrics
- Oracle feed uptime: >99.9%
- Settlement accuracy: 100%
- Average settlement time: <5 minutes after reveal window
- Gas efficiency: Optimized for current network conditions
- Alert response time: <2 minutes for critical issues
