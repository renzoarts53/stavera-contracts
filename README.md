# StaveraTransferRegistry (design, tests and deployment plan)

**Status: compiled and tested locally. 22 tests passed, 0 failed. NOT deployed or verified. No contract address exists yet.**

## 1. Did an original Stavera contract already exist?
In the project files I could see (`index.html`, `vercel.json`, `package.json`), there is no Solidity file, no Foundry/Hardhat config, no deployment script and no deployment record. The only contract addresses in the site are third-party infrastructure (USDC, EURC, cirBTC, Circle CCTP). Those are NOT Stavera contracts and must never be listed as yours.
I cannot see your GitHub repository. To be sure you never deployed one: open your deployer wallet on the Arc explorer and look for transactions of type "contract creation". If there are none, you have no original contract.

## 2. What it does
A small public notebook. Each wallet can write down ITS OWN cross-chain transfers: the source (burn) transaction hash, the route (two Circle CCTP domain numbers), and later the destination (mint) transaction hash. It holds no money and moves no tokens.

## 3. Why Stavera could use it (honest assessment)
Useful, but modest, and optional:
- Recovery without the browser: today a burn hash is saved only in the browser. If a user clears data or switches device, they must find the hash themselves. A registry lets the app list a wallet's past transfers anywhere.
- A shareable, permanent record of "this transfer started here and ended there".
Costs and limits:
- One extra transaction (and MetaMask prompt) per transfer. It must stay opt-in, never required for a bridge.
- A record is self-reported. It does not prove a burn or mint happened. The app must still check the real transactions.
- Everything is public.
Verdict: reasonable as an optional "Save to Stavera registry" feature. It is not necessary for the bridge to work. Only deploy it if you actually want that feature.

## 4. How the app would use it (NOT wired in yet)
After you deploy and verify it, I would add a public address constant to `index.html` (an address is not a secret, so no Vercel environment variable is needed), plus an opt-in checkbox on the Bridge tab: `record()` after the burn is confirmed, `complete()` after the verified mint, `markFailed()` when recovery is needed, and `getTransfers()` to list history. I will wire it only after the real address and the compiled ABI (`forge inspect StaveraTransferRegistry abi`) are confirmed.

## 5. Functions
| Function | Who | What |
|---|---|---|
| `record(sourceTxHash, sourceDomain, destinationDomain)` | any wallet, for itself | create a record (status Started) |
| `complete(sourceTxHash, destinationTxHash)` | the record's owner | set destination hash (status Completed, final) |
| `markFailed(sourceTxHash)` | the record's owner | Started -> Failed (can still be completed later) |
| `getTransfer(owner, sourceTxHash)` | anyone (read) | one record |
| `transferCount(owner)` | anyone (read) | how many records |
| `getTransfers(owner, offset, limit)` | anyone (read) | a page, max 50 |

## 6. Data stored
Per record: status, source domain, destination domain, created/updated time, source tx hash, destination tx hash. No amounts, no recipient addresses, no personal data. (The owner address is the key.)

## 7. Security and privacy
- No owner, no admin, no upgrade, no payable functions, no token or ETH handling. Plain Ether sent to it is rejected.
- Records are keyed by (caller, sourceTxHash): nobody can change or "squat" someone else's record. Tests cover this.
- Inputs validated: non-zero hashes, different domains, no duplicates, valid status changes, page size limit.
- Privacy: it publicly links a wallet to its transfer hashes. Those transactions are already public on-chain, but the registry makes them easy to list. Hence opt-in.
- Not audited. Testnet use only.
- Native USDC on Arc could in theory be force-sent to any address by other means; the contract has no way to move it. Harmless, but note it.

## 8. Can it be deployed and verified on Arc Testnet?
Plausibly yes: it is plain Solidity with no special opcodes. `foundry.toml` targets EVM `paris` conservatively because Arc's supported EVM version was not confirmed. Not verified until you try.

## 9. Build and test (already completed locally; rerun after any code changes)
    # install Foundry first: https://book.getfoundry.sh/getting-started/installation
    cd stavera-contracts
    forge install foundry-rs/forge-std
    forge build
    forge test -vvv

Expected: all tests pass. Send me the output if anything fails.

## 10. Deployment plan (I will NOT deploy anything without your explicit approval)
Cost: a small amount of Arc Testnet USDC for gas (free test tokens).
Your private key must never be pasted into chat, a file or a `.env`. Use a Foundry keystore, which asks for the key only in your own terminal:

    cast wallet import stavera-deployer --interactive

1. Dry run (no transaction is sent):

       forge script script/Deploy.s.sol:Deploy --rpc-url arc_testnet --account stavera-deployer

2. Real deployment, only after you approve:

       forge script script/Deploy.s.sol:Deploy --rpc-url arc_testnet --account stavera-deployer --broadcast

3. Record the real address and the deployment transaction hash from `broadcast/Deploy.s.sol/5042002/run-latest.json`.
4. Confirm code exists: `cast code <ADDRESS> --rpc-url arc_testnet` must NOT print `0x`.

## 11. Verification on ArcScan
1. `forge flatten src/StaveraTransferRegistry.sol > flat.sol`
2. Open https://testnet.arc-scan.org/verifyContract (the page you were given; note the transaction links in Stavera use testnet.arcscan.app, so use whichever host shows your contract).
3. Enter: the contract address; compiler 0.8.24; optimization ON, runs 200; EVM version paris; license MIT; no constructor arguments; paste `flat.sol`.
4. Success means the contract's address page shows it as verified. Do not report it as verified until you have seen that.

## 12. Arc Builder form
Only after step 11 succeeds, the form line is:

    StaveraTransferRegistry, 0xYOUR_REAL_ADDRESS

Until then there is nothing honest to submit.
