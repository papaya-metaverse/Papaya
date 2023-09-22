import { BigNumberish, BigNumber } from 'ethers';
import { Address } from 'hardhat-deploy/types';
import { ethers } from 'hardhat'

import "dotenv/config";

export const getEnv = env => {
    const value = process.env[env];
    if (typeof value === 'undefined') {
      console.log(`${env} has not been set.`);
      return "";
    }
    return value;
  };

export interface networkConfigItem {
    blockConfirmations?: number
    aya: {
        name: string
        symbol: string
        totalSupply: BigNumberish
        admin: Address
    },
    payoutV2: {
        serviceWallet?: Address
        chainPriceFeed?: Address
    },
}

export interface networkConfigInfo {
    [key: string]: networkConfigItem
}

export const networkConfig: networkConfigInfo = {
    mumbai: {
        aya: {
            name: "Papaya Family Token",
            symbol: "AYA",
            totalSupply: "28500000000",
            admin: getEnv('PUBLIC_KEY_DEPLOYER')
        },
        payoutV2: {
            serviceWallet: getEnv('PUBLIC_KEY_SERVICE_WALLET'),
            chainPriceFeed: getEnv('PUBLIC_KEY_PRICE_FEED')
        },
    },
    bsc_testnet: {
        aya: {
            name: "Papaya Family Token",
            symbol: "AYA",
            totalSupply: "28500000000",
            admin: getEnv('PUBLIC_KEY_DEPLOYER')
        },
        payoutV2: {
            serviceWallet: getEnv('PUBLIC_KEY_SERVICE_WALLET'),
            chainPriceFeed: getEnv('PUBLIC_KEY_PRICE_FEED')
        },
    },
    bsc_mainnet: {
        aya: {
            name: "Papaya Family Token",
            symbol: "AYA",
            totalSupply: "28500000000",
            admin: getEnv('PUBLIC_KEY_DEPLOYER')
        },
        payoutV2: {
            serviceWallet: getEnv('PUBLIC_KEY_SERVICE_WALLET'),
            chainPriceFeed: getEnv('PUBLIC_KEY_PRICE_FEED')
        },
    },
    hardhat: {
        aya: {
            name: "PAPAYA Family Token",
            symbol: "AYA",
            totalSupply: "2850000000000",
            admin: getEnv('TEST_PUBLICKEY')
        },
        payoutV2: {
            serviceWallet: getEnv('PUBLIC_KEY_SERVICE_WALLET'),
            chainPriceFeed: getEnv('PUBLIC_KEY_PRICE_FEED')
        },
    }
}

export const developmentChains = ["hardhat"]
