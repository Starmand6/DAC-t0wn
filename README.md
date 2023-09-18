<a name="readme-top"></a>

# Crowdfunding Escrow Platform Using Dominant Assurance

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#about-the-project">About the Project</a></li>
    <li><a href="#dominant-assurance-background">Dominant Assurance Background</a></li>
    <li><a href="#campaign-workflow">Campaign Workflow</a></li>
    <li><a href="#contract-functionality">Contract Functionality</a></li>
    <li><a href="#for-the-devs">For the Devs</a></li>
    <li><a href="#future-considerations">Future Considerations</a></li>
    <li><a href="#lessons-learned">Lessons Learned</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
    <li><a href="#additional-resources">Additional Resources</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->

## About the Project

This repo translates Alex Tabarrok’s “dominant assurance” contract idea to the blockchain (explainer in next section) by being an extension of projects on Juicebox (JB) -- an innovative and highly customizable platform for crowdfunding projects on Ethereum. The main juice of this repo is the dominant assurance escrow contract (DAC) that quadruples as a JB Data Source, JB Pay Delegate, and JB Redemption Delegate for a given JB project. This alternative mechanism can be extended to fund any type of crowdfunding campaign or public good.

-   [Juicebox Docs](https://docs.juicebox.money/dev/)
-   [Juicebox Github](https://github.com/jbx-protocol)
-   Goerli Etherscan Link Placeholder for the deployed [DominantJuice.sol]()

<!-- DOMINANT ASSURANCE BACKGROUND -->

## Dominant Assurance Background

Only [23.6%](https://www.thecrowdfundingcenter.com/data/projects) of crowdfunding campaigns succeed, some of which is due to the [“free rider” problem](https://www.investopedia.com/terms/f/free_rider_problem.asp). History has also shown that campaigns that have [reached at least 30%](https://www.fundera.com/resources/crowdfunding-statistics) of their funding in the first week have a greater chance of achieving their final goal. [Dominant assurance](https://foresight.org/summary/dominant-assurance-contracts-alex-tabarrok-george-mason-university/) seeks to simultaneously minimize free riders while ensuring earlier pledging.

The key concept lies in incentivizing early and significant contributions. Before the start of a crowdfunding campaign, the campaign creator locks their own funds in a dominant assurance smart contract that they or their team owns. If the campaign fails, pledgers get a full refund along with a portion of the locked funds, as a refund bonus, according to a custom formula that is based on how early and large their pledge was. Ideally, the refund bonus formula is a type of exponential decay. The secret sauce is in finding the right formula for your project that incentivizes pledgers to raise funds above the 30% threshold very early in the campaign. If the campaign succeeds, the pledgers get the goods but no bonuses, and the complete refund bonus can be wihdrawn by the campaign owner after the campaign ends. This creates a win-win situation for early pledgers, who either get a return on their pledge or get the desired good if the campaign goal is met.

Overall, the transparency and deterministic characteristics of smart contracts help to minimize pledger risk and encourage wider participation, increasing chances of success. Using the dominant assurance mechanism also sends a message to your potential pledgers that you believe in your project so much that you are willing to put your own money at stake for the success of the project.

<!-- CAMPAIGN WORKFLOW -->

## Campaign Workflow

### Campaign Setup

-   The project team executes the LaunchProjectAndDeployDAC.s.sol script by running `forge script` with the specific project parameters (owner address, cycle target, cycle start time, duration, minimum pledge amount, and project metadata). For details on using scripting with Forge, see the <a href="#for-the-devs">For the Devs</a> section below.
    -   The script first pre-computes the dominant assurance contract (DominantJuice.sol / DAC) address and populates all JB data structs necessary to create a JB project (with dominant-assurance-informed parameters) that will be linked to the DAC.
    -   `launchProjectFor()` is called with all parameters on the JB Controller and a `projectId` is created and returned.
    -   Using the `projectId` along with the team-specified project parameters, the DAC is finally created and deployed to the Goerli testnet or Mainnet.
    -   To allow for project and contract setup vetting, the cycle start time should be set a day or two in the future. If the project wasn't created correctly or there was an entry mistake, the team does not deposit the refund bonus and abandon the project and contract in place. (Pledgers will not be able to pledge until the refund bonus has been deposited.) The initial gas fee is lost, but JB architecture will just go on with the next projectID, and the creator can deploy a new DAC linked to a new ID.
-   Once the team vets and approves the setup, the project creator / multisig deposits the refund bonus in ETH into the Data Source / DominantJuice contract.

### During Campaign / Main Project Funding Cycle

-   The main campaign cycle begins and pledgers will pledge funds through the regular Juicebox UI / front end.
-   The project is set so that cycle #1 (main campaign cycle) does not allow redemptions, distributions, burns, or token transfers of any kind. Users can only pledge.
-   As the campaign funding cycle nears close, the project's next cycle will need to be configured via a reconfigure script or the project's management page on Juicebox's site (juicebox.money or goerli.juicebox.money). Either way, the cycle configuration changes are made by calling `reconfigureFundingCyclesOf()` on the JBController.
    -   If running ReconfigureFundingCycle.s.sol with `forge script`, the aforementioned function is called with preset parameters (`_projectId`, `_result`, `_cycleDuration`, `_delegate`), where `_result` depends on the funding status:
        -   If the campaign has **failed**, `_result` is set to `0`, which send the following to Juicebox:
            -   `pauseTransfers`: false
            -   `redemptionRate`: 100%
            -   `pauseDistributions`: true
            -   `pauseRedeem`: false
            -   `pausePay`: true
            -   `pauseBurn`: false
            -   `useDataSourceForPay`: false
            -   `useDataSourceForRedeem`: true
        -   If the campaign is **successful**, `_result` is set to `1`, which sends the following to Juicebox:
            -   `pauseTransfers`: true
            -   `redemptionRate`: 0%
            -   `pauseDistributions`: true
            -   `pauseRedeem`: true
            -   `pausePay`: true
            -   `pauseBurn`: true
            -   `useDataSourceForPay`: false
            -   `useDataSourceForRedeem`: false
        -   If the cycle is almost over, but the outcome is still **unclear**, then `_result` should be set to `2`, which creates a "buffer" cycle, which does not allow any movement of funds for anyone. When the campaign expires, the project team can be 100% confident in the final results and can use the script to call `reconfigureFundingCyclesOf()` again, now with a `_result` of `0` or `1` as detailed above. A `_result` of `2` sends the following to Juicebox:
            -   `pauseTransfers`: true
            -   `redemptionRate`: 0%
            -   `pauseDistributions`: true
            -   `pauseRedeem`: true
            -   `pausePay`: true
            -   `pauseBurn`: true
            -   `useDataSourceForPay`: false
            -   `useDataSourceForRedeem`: false
    -   If reconfiguring via the Juicebox website, the project creator/managers manually enters the parameters above as appropriate guided by the solid JB UI.

### Campaign Close

-   For failed cycles/campaigns, pledgers can redeem their full pledge via the project page on the Juicebox website, which calls `didRedeem()` on the DAC (the JB Redemption Delegate here), which sends the pledger a refund bonus determined by the preset formula. If a pledger loses control of the wallet address they used to pledge, after a predetermined lock period, the campaign creator/manager can use the contingency function to withdraw and send the funds to the affected pledger. See section below for details.
-   For successful cycles/campaigns, the project creator can call `creatorWithdraw()` on the DAC to retrieve the funds they originally deposited.
-   The DAC and JB platform have fulfilled their duties.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRACT FUNCTIONALITY -->

## Contract Functionality - DominantJuice.sol

-   `constructor()` populates `campaign.projectId`, `campaign.cycleTarget`, `campaign.minimumPledgeAmount`, `campaign.cycleStart`, `campaign.cycleExpiry`, and JB platform addresses, effectively readying the campaign:
    -   `JBController`: tracks and manages funding cycles and project tokens
    -   `JBDirectory`: tracks and manages payment terminals and controller for each project
    -   `JBFundAccessConstraintsStore`: Information pertaining to how much funds can be accessed by a project from each payment terminal
    -   `JB Single Payment Terminal Store`:
    -   `JBPaymentTerminal`: manages all inflows and outflows of funds for projects using said terminal
-   `supportsInterface()` indicates if the contract adheres to each specified interface.
-   `depositRefundBonus()` allows the contract owner to deposit the refund bonus and emits a `RefundBonusDeposited` event.
-   `payParams()` satisfies JB Data Source interface requirements and is called through the JB architecture when the project receives a payment. It can only be called after both the refund bonus has been deposited and the campaign/cycle has started. It checks that the value of the pending pledge is above the `miniumPledgeAmount` and passes the call chain back to JB.
-   `didPay()` gets called toward the end of the payment call chain via JB, after the payment has been recorded and sent, and can only be called by the project's `paymentTerminal`. It can only be called after both the refund bonus has been deposited and the campaign/cycle has started. For DominantJuice, now acting as the JB Pay Delegate, the function stores pledger and payment data for total pledge amount calculations, as well as pre-calculating pledge weights to be used for determining each pledger's refund bonus should the need arise.
-   `redeemParams()` is called via JB architecture when a payer redeems their JB tokens. The calling function is nonReentrant. If the dominant assurance cycle has not expired, has met the funding target, the caller has never pledged, or the caller has already been refunded, this function will revert. Like `payParams`, it also satisfies JB Data Source interface requirements.
-   `didRedeem()` is executed in the same call chain as `redeemParams()` but happens after the pledge redemption has been recorded and funds have been sent to the redeemer. It has the same gating as `redeemParams()` with an additional requirement that the caller must be a payment terminal of the linked project. In DominantJuice, now acting as the JB Redemption Delegate, it uses a pledger's pledge weight to calculate the refund bonus, which is sent to the pledger, and an event is emitted.
-   `creatorWithdraw()` checks to see if the caller is the contract owner, if campaign has expired, and if the funding goal has been met. If all three are true, the owner can withdraw some or all of the refund bonus they deposited. (They can also withdraw it to any address they want.) Successful execution emits a creator withdrawal event. In the event that a pledger cannot withdraw their refund bonus after a failed campaign, once a predetermined, preprogrammed, and immutable lock period expires (for example, two weeks), the creator can withdraw any stuck funds and send to affected pledgers.
-   `Getters()`:
    -   `getCampaignInfo()` retrieves main campaign parameters: `projectId`, `cycleTarget`, `cycleStart`, `cycleExpiryDate`, `minimumPledgeAmount`, `totalRefundBonus`
    -   `getBalance()` gets contract balance, which will either equal 0 or the `totalRefundBonus`
    -   `isTargetMet()` is true if the total amount of pledges equals or exceeds `cycleTarget`
    -   `hasCycleExpired()` is true when `block.timestamp` is equal to or greater than `cycleExpiryDate`
    -   `getCycleFundingStatus()` returns `totalAmountPledged`, `percentOfGoal`, and `isTargetMet`, `hasCycleExpired`, and `hasCreatorWithdrawnAllFunds` booleans
    -   `getPledgerRefundStatus()` returns whether a pledger has retrieved their refund or not

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- FOR THE DEVS -->

## For the Devs

For quickstart, in a parent directory of your choosing, `git clone` the repo using the link from Github and `cd` into folder. If you don't have Foundry/Forge, run `curl -L https://foundry.paradigm.xyz | bash`, then run `foundryup` to update to latest version. (More detailed instructions can be found in the excellent [Foundry Book](https://book.getfoundry.sh/getting-started/installation)). Run `yarn install` to install included dependencies, which will also run `forge install` for you. (More dependency details can be found here: [Juicebox Contract Template](https://github.com/jbx-protocol/juice-contract-template).)

### Development Stack, Plugins, Libraries, and Dependencies

-   Smart contracts, scripting, and testing: Solidity and Foundry
-   OpenZeppelin inherited contracts: Access Control
-   The wizardry [PRBMath](https://github.com/PaulRBerg/prb-math) for decimal math and exponentiation functionality
-   The fresh and finest imports from the land of Juicebox

### Forge Scripting

-   For going deep into Forge scripting, check out the following resources:
    -   [Forge Scripting Tutorial](https://book.getfoundry.sh/tutorials/solidity-scripting)
    -   [Forge Script Reference Documentation](https://book.getfoundry.sh/reference/forge/forge-script)
    -   [Github Issue #2125](https://github.com/foundry-rs/foundry/issues/2125) - passing arguments into `run()` for use in a script
-   Before running scripts, if using a `.env` file for private keys, run `source .env` at the command line. This "loads" access to environment variables in the CLI. Here are full examples using this project's scripts:
    -   For launching a JB project and deploying the DAC on Goerli: `forge script script/LaunchProjectAndDeployDAC.s.sol --rpc-url $GOERLI_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv --sig "run(address,uint256,uint256,uint256,uint256,string)" <insert deployer address here> 10000000000000 1694647825 1800 1000000000000 "<insert IPFS CID string here>"`
    -   For assigning the campaign manager role after deployment on Goerli: `forge script script/AssignCampaignManagerRole.s.sol --rpc-url $GOERLI_RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv --sig "run(address,address)" <insert DAC Goerli address here> <insert deployer address here>`
-   `forge script --help` can also be run at any time to access help information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- FUTURE CONSIDERATIONS -->

## Future Considerations

-   Accepting payments in tokens other than ETH
-   Multiple campaigns in one contract
-   Many more....

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

## Acknowledgments

Thanks to Scott Auriat for his consultation on different aspects, as well as finding Alex Tabarrok's dominant assurance strategy. Of course, thanks to Alex Tabarrok himself. Also, thank you so much to mdnatx for being a shepherd in the dark forest.

A big thanks to the Juicebox devs for prompt, solid AF assistance and guidance.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ADDITIONAL RESOURCES -->

## Additional Resources

[Foundry Book](https://book.getfoundry.sh/)
[Rapid Tables](https://www.rapidtables.com/)
[WolframAlpha](https://www.wolframalpha.com/)
[Epoch Converter](https://www.epochconverter.com/)
[Ethereum Unit Converter](https://eth-converter.com/)

<p align="right">(<a href="#readme-top">back to top</a>)</p>
