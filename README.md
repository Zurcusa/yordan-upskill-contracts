# Zurcus NFT Auction Contracts

A lightweight, gas-optimized suite of Solidity 0.8.30 contracts that lets anyone mint an ERC-721 collectible and instantly launch an English-style auction for it.  The codebase is **100 % Foundry-native** and comes with ready-made scripts, tests, and Anvil workflows so you can be up and running in minutes.

---

## Contracts

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **`ZurcusNFT.sol`** | ERC-721 collection | • Enum-based sale phases (Whitelist / Public)<br/>• Payable `mint()` with max supply & per-wallet limits<br/>• Role-based whitelist (`WHITELISTED_ROLE`)<br/>• Gas-efficient state packing & custom errors<br/>• Public getters `mintedCount()` and `WHITELISTED_ROLE()` |
| **`AuctionFactory.sol`** | Trust-minimised auction deployer | • Single call to create & initialise auctions<br/>• Maps `bytes32` salts → auction addresses (`liveAuctions`)<br/>• Emits `AuctionCreated` for easy indexing<br/>• Unchecked array push & packed storage for low gas |
| **`Auction.sol`** | English auction per NFT | • Strict `enum AuctionState` instead of bit flags<br/>• Custom errors & NatSpec for every revert path<br/>• `onlyOwner` access to cancel / settle<br/>• Immutable parameters & packed vars for gas<br/>• Public `endAt()`, `highestBid()`, `highestBidder()` getters |

---

## Project Layout (excerpt)

```
contracts/            → core Solidity sources
lib/                  → external libraries
script/               → Forge scripts (deploy & lifecycle)
tests/                → Foundry unit & integration tests
```

---

## Quick Start

### 1. Prerequisites

* [Foundry](https://book.getfoundry.sh/) (`curl -L https://foundry.paradigm.xyz | bash`)
* An RPC endpoint (Alchemy, Infura, local Anvil, …)
* A funded EOA private key for testnet / mainnet broadcasts

### 2. Configure Environment Variables

1. Copy the sample file:
   ```bash
   cp env.example .env
   ```
2. Fill in the values:
   * `TEST_ACCOUNT_1_PRIVATE_KEY` – EOA that will deploy / mint
   * `RPC_URL` – network RPC endpoint (only needed when forking / broadcasting)
   * `MINT_PUBLIC_PRICE` – mint price in wei
   * `AUCTION_DURATION` – auction length in seconds
   * `AUCTION_MIN_BID_INCREMENT` – minimum bid step

---

## Deploy Walkthrough

All scripts live under `script/` and inherit from `EnvLoader.s.sol`, so **all configuration is read from `.env`**.

### A. Deploy the NFT Collection

```bash
forge script script/DeployZurcusNFT.s.sol \
  --rpc-url $RPC_URL --broadcast -vvvv
```
> Outputs the NFT contract address which you will need for the next steps.

### B. Deploy the Auction Factory

```bash
forge script script/DeployFactory.s.sol \
  --rpc-url $RPC_URL --broadcast -vvvv
```

### C. Mint an NFT & Create Its Auction

```bash
forge script script/MintAndCreateAuction1.s.sol \
  --rpc-url $RPC_URL --broadcast -vvvv
```
This script will:
1. Flip the NFT to *PublicSale* phase.
2. Call `mint()` sending the `MINT_PUBLIC_PRICE`.
3. Create an `Auction` via the factory.
4. Approve the auction to transfer the token.

The console log prints the newly-deployed auction address.

### D. Start (Kick-off) the Auction

```bash
forge script script/StartAuction1.s.sol \
  --rpc-url $RPC_URL --broadcast -vvvv
```

Once started, anyone can out-bid the current highest bid until `endAt()`.

---

## Running Tests

```bash
forge test                       # all tests
forge test --match-path contracts/Auction.t.sol      # single suite
```

An Anvil fork is spun up automatically; no manual chain management required.

---

## License

MIT © 2024 Zurcus
