module.exports = {
  apps: [
    // Oracle Feeders (Mainnet)
    {
      name: 'oracle-mainnet-1',
      script: 'daemon/oracleBot.ts',
      interpreter: 'tsx',
      env: {
        NODE_ENV: 'production',
        NETWORK: 'mainnet',
        RPC_URL: process.env.ALCHEMY_MAINNET_RPC,
        ORACLE_PRIVATE_KEY: process.env.ORACLE_1_PRIVATE_KEY,
        INSTANCE_ID: '1'
      },
      max_memory_restart: '500M',
      restart_delay: 5000,
      max_restarts: 10,
      min_uptime: '10s'
    },
    {
      name: 'oracle-mainnet-2', 
      script: 'daemon/oracleBot.ts',
      interpreter: 'tsx',
      env: {
        NODE_ENV: 'production',
        NETWORK: 'mainnet', 
        RPC_URL: process.env.INFURA_MAINNET_RPC,
        ORACLE_PRIVATE_KEY: process.env.ORACLE_2_PRIVATE_KEY,
        INSTANCE_ID: '2'
      },
      max_memory_restart: '500M',
      restart_delay: 5000,
      max_restarts: 10,
      min_uptime: '10s'
    },
    {
      name: 'oracle-mainnet-3',
      script: 'daemon/oracleBot.ts', 
      interpreter: 'tsx',
      env: {
        NODE_ENV: 'production',
        NETWORK: 'mainnet',
        RPC_URL: process.env.QUICKNODE_MAINNET_RPC, 
        ORACLE_PRIVATE_KEY: process.env.ORACLE_3_PRIVATE_KEY,
        INSTANCE_ID: '3'
      },
      max_memory_restart: '500M',
      restart_delay: 5000,
      max_restarts: 10,
      min_uptime: '10s'
    },

    // Settlement Bots (Mainnet)
    {
      name: 'settler-mainnet',
      script: 'bots/settleBot.ts',
      interpreter: 'tsx', 
      env: {
        NODE_ENV: 'production',
        NETWORK: 'mainnet',
        RPC_URL: process.env.MAINNET_RPC,
        SETTLER_PRIVATE_KEY: process.env.SETTLER_PRIVATE_KEY
      },
      max_memory_restart: '300M',
      restart_delay: 3000,
      max_restarts: 10,
      min_uptime: '10s'
    },
    {
      name: 'threshold-mainnet',
      script: 'bots/commitRevealBot.ts',
      interpreter: 'tsx',
      env: {
        NODE_ENV: 'production', 
        NETWORK: 'mainnet',
        RPC_URL: process.env.MAINNET_RPC,
        THRESHOLD_PRIVATE_KEY: process.env.THRESHOLD_PRIVATE_KEY
      },
      max_memory_restart: '300M',
      restart_delay: 3000,
      max_restarts: 10,
      min_uptime: '10s'
    },

    // Monitoring & Management (Mainnet)
    {
      name: 'monitor-mainnet',
      script: 'daemon/monitoringAgent.ts',
      interpreter: 'tsx',
      env: {
        NODE_ENV: 'production',
        NETWORK: 'mainnet',
        RPC_URL: process.env.MAINNET_RPC,
        MONITORING_PORT: '3001'
      },
      max_memory_restart: '200M',
      restart_delay: 5000,
      max_restarts: 10,
      min_uptime: '10s'
    },
    {
      name: 'manager-mainnet',
      script: 'daemon/managerAgent.ts', 
      interpreter: 'tsx',
      env: {
        NODE_ENV: 'production',
        NETWORK: 'mainnet',
        RPC_URL: process.env.MAINNET_RPC,
        MANAGER_PORT: '3002'
      },
      max_memory_restart: '200M',
      restart_delay: 5000,
      max_restarts: 10,
      min_uptime: '10s'
    },

    // Testnet versions (for parallel testing)
    {
      name: 'oracle-testnet-1',
      script: 'daemon/oracleBot.ts',
      interpreter: 'tsx',
      env: {
        NODE_ENV: 'development',
        NETWORK: 'sepolia',
        RPC_URL: process.env.SEPOLIA_RPC,
        ORACLE_PRIVATE_KEY: process.env.TESTNET_ORACLE_1_KEY,
        INSTANCE_ID: '1'
      },
      max_memory_restart: '300M'
    },
    {
      name: 'settler-testnet',
      script: 'bots/settleBot.ts',
      interpreter: 'tsx',
      env: {
        NODE_ENV: 'development',
        NETWORK: 'sepolia', 
        RPC_URL: process.env.SEPOLIA_RPC,
        SETTLER_PRIVATE_KEY: process.env.TESTNET_SETTLER_KEY
      },
      max_memory_restart: '200M'
    }
  ],

  deploy: {
    production: {
      user: 'bbod',
      host: ['prod-1.bbod.io', 'prod-2.bbod.io', 'prod-3.bbod.io'],
      ref: 'origin/main',
      repo: 'git@github.com:bbod-finance/bbod.git',
      path: '/var/www/bbod',
      'pre-deploy-local': '',
      'post-deploy': 'npm install && npm run build && pm2 reload ecosystem.config.js --env production',
      'pre-setup': '',
      env: {
        NODE_ENV: 'production'
      }
    },
    staging: {
      user: 'bbod',
      host: 'staging.bbod.io',
      ref: 'origin/develop',
      repo: 'git@github.com:bbod-finance/bbod.git', 
      path: '/var/www/bbod-staging',
      'post-deploy': 'npm install && npm run build && pm2 reload ecosystem.config.js --env staging',
      env: {
        NODE_ENV: 'staging'
      }
    }
  }
};
