<a name="readme-top"></a>

# Crowdfunding Escrow Platform Using Dominant Assurance

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#about-the-project">About The Project</a></li>
    <li><a href="#dominant-assurance-background">Dominant Assurance Background</a></li>
    <li><a href="#project-workflow">Project Workflow</a></li>
    <li><a href="#contract-functionality">Contract Functionality</a></li>
    <li><a href="#for-the-devs">For The Devs</a></li>
    <li><a href="#future-considerations">Future Considerations</a></li>
    <li><a href="#lessons-learned">Lessons Learned</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->

## About The Project

This repo translates Alex Tabarrok’s “dominant assurance” contract idea to the blockchain (explainer in next section) by being an extenion of Juicebox (JB) -- an innovative and HIGHLY customizable platform for crowdfunding projects on Ethereum. The main juice of this repo is the dominant assurance escrow contract that quadruples as a JB Data Source, JB Pay Delegate, and JB Redemption Delegate for a given JB project. This alternative mechanism can be extended to fund any type of crowdfunding campaign or public good.

-   [Juicebox Docs](https://docs.juicebox.money/dev/)
-   [Juicebox Github](https://github.com/jbx-protocol)
-   Contracts on Goerli Etherscan (PLACEHOLDERS ONLY. OLD LINKS HAVE BEEN REMOVED)
    -   [DominantJuice.sol]()
    -   [MyDelegateDeployer.sol (verified)]()
    -   [DelegateProjectDeployer.sol (verified)]()
-   Front End coming soon
-   Front End Github soon

<!-- DOMINANT ASSURANCE BACKGROUND -->

## Dominant Assurance Background

Only [23.6%](https://www.thecrowdfundingcenter.com/data/projects) of crowdfunding campaigns succeed, some of which is due to the [“free rider” problem](https://www.investopedia.com/terms/f/free_rider_problem.asp). History has also shown that campaigns that have [reached at least 30%](https://www.fundera.com/resources/crowdfunding-statistics) of their funding in the first week have a greater chance of achieving their final goal. [Dominant assurance](https://foresight.org/summary/dominant-assurance-contracts-alex-tabarrok-george-mason-university/) seeks to simultaneously minimize free riders while ensuring earlier pledging.

The key concept lies in incentivizing early and significant contributions. Before the start of a crowdfunding campaign, the campaign creator locks their own funds that will be used as a refund bonus in a dominant assurance smart contract that they or their team owns. If the campaign fails, pledgers get their full refund along with a portion of the refund bonus according to a custom formula that can be coded in for each project, based on how early and large their pledge was. Ideally, the refund bonus formula is a type of exponential decay. The secret sauce is in finding the right formula for your project that incentivizes pledgers to raise funds above the 30% threshold very early in the campaign. If the campaign succeeds, the pledgers get the goods but no bonuses, and the complete refund bonus can be wihdrawn by the campaign owner. This creates a win-win situation for early pledgers, who either get a return on their pledge or get the desired good if the campaign goal is met.

Overall, the transparency and deterministic characteristics of the smart contracts help to minimize pledger risk and encourage wider participation, increasing chances of success. Using the dominant assurance mechanism also sends a message to your potential pledgers that you believe in your project so much that you are willing to put your own money at stake for the success of the project.

<!-- PROJECT WORKFLOW -->

## Project Workflow

The workflow is separated for the project creator and pledgers. Any potential pledger can interact with the JB front end as they do for any project. Nothing different happens on their side. The project creator team can develop a standalone front end or, perhaps in the future, can choose to check a dominant assurance box while setting up a Juicebox project, which would then add all the new dominant assurance information and functions, as well as adding a dominant assurance section in the creator project page.

-   The project team's developer(s) can run `forge script` with the DeployContracts.s.sol script to deploy DelegateProjectDeployer.sol. onto the Goerli testnet or Mainnet.
-   When a project creator or owner creates their project by calling `DelegateProjectDeployer.launchProjectFor()` with their specific project parameters (owner address, cycle target, duration, etc.), the call chain starts by retrieving the current projects count from the JB Controller (which oversees project funding cycles) and optimistically adds 1 to get the next project ID for the about-to-be-created project. It then calls `DelegateProjectDeployer.deployDelegateFor()`, which both deploys the Data Source / Dominant Assurance Escrow Contract AKA DominantJuice.sol and also initializes it with the pertinent parameters. It then sends the remaining parameters, inlcuding the newly deployed Data Source's contract address, to the JB Controller and remaining architecture, which continue the call chain to create the actual project on the Juicebox platform.
    -   Tip: Specify cycle start a day or two out to give time to double check if the project was set correctly on JB, that the Dominant Assurance contract was initialized correctly, and to deposit the refund bonus if so. Pledgers will not be able to pledge until the refund bonus has been deposited. If the project wasn't created correctly or there was a mistake when inputting the parameters, teams can just not deposit the refund bonus and start over by calling `DelegateProjectDeployer.launchProjectFor()` again. They would still lose the initial gas fee of course, but JB architecture would just go on with the next projectID, and the creator can deploy a new Data Source based off that ID, and the previous Data Source would be abandoned.
-   If all looks good, the project creator deposits the refund bonus in ETH into the Data Source / DominantJuice contract.
-   Project Funding Cycle begins:
    -   Pledgers can pledge funds through the regular Juicebox UI.
    -   No redemptions, no distributions, and no token transfers for cycle 1.
-   As the Funding Cycle nears close and the results become clear, the project's next cycle will need to be configured. At present, if the cycle is almost over, but the outcome is still unclear, then the project owner would call `DelegateProjectDeployer.reconfigureFundingCyclesOf()` with the projectID and a "0", which would create a two-day "dummy" cycle 2, which doesn't allow any movement of funds for anyone. This ensures that the first cycle has expired, and the results are 100% printed on the blockchain. The project owner can then call `reconfigureFundingCyclesOf()` again, now that the results are fully known, and can input "1" for a successful campaign or "2" for a failed campaign. This can also be done via the standalone front end UI. Either way, the following parameters are adjusted depending on the first cycle's results:
    -   Failed campaign: `pauseTransfers`: false, `redemptionRate`: 100%, `pauseDistributions`: true, `pauseRedeem`: false `pausePay`: true, `pauseBurn`: false, `useDataSourceForPay`: false, `useDataSourceForRedeem`: true,
    -   Successful campaign: `pauseTransfers`: false, `redemptionRate`: 0%, `pauseDistributions`: false, `pauseRedeem`: true `pausePay`: true, `pauseBurn`: false, `useDataSourceForPay`: false, `useDataSourceForRedeem`: false,
-   After cycle completion, the creator or pledgers or literally anyone can call `relayCycleResults()`, which opens one of the withdraw functions:
    -   For failed cycles/campaigns, pledgers can redeem all their tokens via the Juicebox UI, which calls `redeemTokensOf()` on the `JBPayoutRedemptionTerminal`, which calls `didRedeem()` in DominantJuice (the JB Redemption Delegate here), which sends the pledger a refund bonus determined by the set formula.
    -   For successful cycles/campaigns, the project creator can call `creatorWithdraw()` on the DominantJuice contract to retrieve the funds they deposited at the beginning.
-   The Dominant Assurance DominantJuice contract has fulfilled its duties.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRACT FUNCTIONALITY -->

### DominantJuice.sol Contract Functionality

-   `initialize()` populates Juicebox `projectID`, `cycleTarget`, `minimumPledgeAmount`, and JB Controller and Payment Terminal Store deployed addresses, effectively readying the project.
-   `depositRefundBonus()`: allows the contract owner to deposit the refund bonus and emits a `RefundBonusDeposited` event.
-   `payParams()` gets called through the JB architecture when the project receives a payment. The funtionality it offers DominantJuice is connecting it with the JB payment flow, function gating via initialization, and requiring a `miniumPledgeAmount`.
-   `didPay()` gets called toward the end of the payment call chain via JB and can only be called by the project's `paymentTerminal`. For DominantJuice, now acting as the JB Pay Delegate, it stores pledger and payment data for reading later, as well as providing the inputs for calculating the refund bonus should the need arise.
-   `relayCycleResults()` can be called by anyone after the campaign expires. It sets the `isCampaignExpired` boolean and the contract's (and funding cycle's) fund balance. With those two variables set, it calculates the `isTargetMet` boolean. It also emits a `CampaignHasClosed` event.
-   `redeemParams()` is called from JBSingleTokenPaymentTerminalStore3_1_1 when `recordRedemptionFor()` is called (when a payer redeems their tokens). The calling function is nonReentrant. It introduces withdrawal function gating. If the dominant assurance cycle has not expired, has met the funding target, the caller has never pledged, or the caller has already been refunded, this function will revert.
-   `didRedeem()` is executed in the same call chain as `redeemParams()` but happens much later, after the main pledge redemption has actually gone through. It also has the exact same gating as `redeemParams()` since it is an external function and can be called directly. In DominantJuice, now acting as the JB Redemption Delegate, it uses a helper function to calculate the refund bonus, which is sent to the pledger, and an event is emitted.
-   `creatorWithdraw()` checks to see if the caller is the contract owner, if campaign has expired, and if the funding goal has been met. If all three are true, then owner can withdraw some or all of the refund bonus they deposited. (They can also withdraw it to any address they want.) Successful execution emits a creator withdrawal event.
-   `Getters()`:
    -   `calculateRefundBonus()` is helper/getter function that calculates the individual refund bonus for an address. The refund bonus is an exponential decay formula that weights how early and how large a given pledge was.
    -   `getBalance()` gets contract balance.
    -   `getCycleFundingStatus()` returns `totalAmountPledged`, `percentOfGoal`, an `isTargetMet` boolean, and a `hasCreatorWithdrawnAllFunds` boolean.
    -   `getPledgerAmount()` is a convenience function.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- FOR THE DEVS -->

## For The Devs

For quickstart, in a parent directory of your choosing, `git clone` the repo using the link from Github and `cd` into folder. If you don't have Foundry/Forge, run `curl -L https://foundry.paradigm.xyz | bash`, then run `foundryup` to update to latest version. (More detailed instructions can be found in the excellent [Foundry Book](https://book.getfoundry.sh/getting-started/installation)). Run `yarn install` to install included dependencies, which will also run `forge install` for you.

### Development Stack, Plugins, Libraries, and Dependencies

-   Smart contracts, scripting, and testing: Solidity and Foundry
-   OpenZeppelin inherited contracts: Ownable, ReentrancyGuard
-   The fresh and finest imports from the land of Juicebox
-   Front End: TBD

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- FUTURE CONSIDERATIONS -->

## Future Considerations

-   Accepting payments in tokens other than ETH.
-   In a failed campaign, if pledgers forget to withdraw their refund bonus or lose their keys to their address, add functionality to retrieve their funds and somehow get them back to them. Could make the function only callable a week after the `campaignExpiryDate` to instill confidence that owner will not abuse the responsibility.
-   Add more getter functions like totalAmountRefunded, etc.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LESSONS LEARNED -->

## Lessons Learned

Things are never permanently stuck. Sometimes all it takes is a good night's sleep, and the answer presents itself in the morning.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->

## Contributing

Scott Auriat was the main consultant and sounding board for this project. mdnatx was the senior dev who helped do reviews and steer me in the right directions!

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->

## License

Distributed under the MIT License.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTACT -->

## Contact

Armand Daigle - [@\_Starmand](https://twitter.com/_Starmand) - armanddaoist@gmail.com

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ACKNOWLEDGMENTS -->

## Acknowledgments and Resources

Thanks to Scott Auriat for his consultation on different aspects, as well as introducing me to the dominant assurance strategy. Thank you so much to mdnatx for taking the time to shepherd me through the dark forest.

A big thanks to the Juicebox devs for prompt, solid AF assistance and guidance.

<p align="right">(<a href="#readme-top">back to top</a>)</p>
