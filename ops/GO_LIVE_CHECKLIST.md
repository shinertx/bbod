# 🚀 BBOD Production Go-Live Checklist

## 4-Week Structured Launch Plan

### Week 1: Security Audit & Final Testing
See [SECURITY_AUDIT.md](./SECURITY_AUDIT.md) for detailed checklist
- [ ] Static analysis (Slither, Mythril) completed
- [ ] Test coverage >95% on critical paths  
- [ ] Economic security review passed
- [ ] All critical vulnerabilities resolved
- [ ] Integration test suite passing

### Week 2: Testnet Deployment & Integration Testing  
See [TESTNET_DEPLOYMENT.md](./TESTNET_DEPLOYMENT.md) for detailed checklist
- [ ] All contracts deployed to Sepolia testnet
- [ ] Oracle feeders operational (3+ distinct RPCs)
- [ ] Settlement bots running with restart policies
- [ ] Frontend deployed and tested
- [ ] 48+ hours continuous operation validated
- [ ] All integration scenarios passed

### Week 3: Mainnet Deployment & Infrastructure Setup
See [MAINNET_DEPLOYMENT.md](./MAINNET_DEPLOYMENT.md) for detailed checklist  
- [ ] Safe multisig deployed and tested (3/5 or 2/3 signers)
- [ ] All contracts deployed via Safe and verified on Etherscan
- [ ] Production infrastructure deployed (3+ geographic regions)
- [ ] Oracle feeders operational with distinct RPC endpoints
- [ ] Settlement & threshold bots running with monitoring
- [ ] Operations wallet funded with 8+ ETH gas buffer
- [ ] Monitoring stack deployed (Prometheus + Grafana)
- [ ] Alert rules configured and emergency procedures tested

### Week 4: Frontend Launch & Monitoring Validation
See [FRONTEND_LAUNCH.md](./FRONTEND_LAUNCH.md) for detailed checklist
- [ ] Production frontend deployed with proper optimization
- [ ] Domain, SSL, and CDN configured
- [ ] User documentation and onboarding complete
- [ ] Performance monitoring and analytics setup
- [ ] Soft launch with limited users successful
- [ ] Public launch executed smoothly
- [ ] First week >99.5% uptime achieved

## Critical Success Metrics
- **Security**: Zero critical vulnerabilities, full audit completion
- **Reliability**: >99.5% uptime across all systems
- **Performance**: Settlement <5min after reveal, gas optimized
- **User Experience**: Frontend Lighthouse score >90 across all metrics
- **Financial**: Successful handling of real user funds and transactions

## Emergency Procedures
- **Kill Switch**: [KILLSWITCH.md](./KILLSWITCH.md)
- **Incident Response**: 24/7 monitoring with <5min response to critical alerts
- **Backup Systems**: All bots with auto-restart, multiple RPC endpoints
- **Communication**: User notification system via frontend and social mediaSafe owners confirmed & hardware wallets tested
- [ ] 3 oracle feeders online (distinct RPCs)
- [ ] commitRevealBot + daemon + settleBot on PM2 with restart-on-fail
- [ ] 8 ETH gas buffer in Safe “ops” wallet
- [ ] Verified contracts on Etherscan
- [ ] Front-end NEXT_PUBLIC_* envs set & redeployed
