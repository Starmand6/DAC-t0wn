<a name="readme-top"></a>

# Crowdfunding Escrow Platform Using Dominant Assurance

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#about-the-project">About The Project</a></li>
    <li><a href="#dominant-assurance-background">Dominant Assurance Background</a></li>
    <li><a href="#project-technicals">Project Technicals</a></li>
    <li><a href="#project-workflow">Project Workflow</a></li>
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

This is a Juicebox Delegate Hackathon project repo that translates Alex Tabarrok’s “dominant assurance” contract idea to the blockchain (explainer in next section). Juicebox (JB) is an innovative and HIGHLY customizable platform for crowdfunding projects on Ethereum. The main juice of this repo is the dominant assurance escrow contract that quadruples as a JB Data Source, JB Pay Delegate, and JB Redemption Delegate for a given JB project. This alternative mechanism can be extended to fund any type of crowdfunding campaign or public good.

- [Juicebox docs](https://docs.juicebox.money/dev/)
- [Juicebox Github](https://github.com/jbx-protocol)

<!-- DOMINANT ASSURANCE BACKGROUND -->

## Dominant Assurance Background

Only [23.6%](https://www.thecrowdfundingcenter.com/data/projects) of crowdfunding campaigns succeed, some of which is due to the [“free rider” problem](https://www.investopedia.com/terms/f/free_rider_problem.asp). History has also shown that campaigns that have [reached at least 30%](https://www.fundera.com/resources/crowdfunding-statistics) of their funding in the first week have a greater chance of achieving their final goal. [Dominant assurance](https://foresight.org/summary/dominant-assurance-contracts-alex-tabarrok-george-mason-university/) seeks to simultaneously minimize free riders while ensuring earlier pledging.

The key concept lies in incentivizing early and significant contributions. Before the start of a crowdfunding campaign, the campaign creator locks their own funds that will be used as a refund bonus in a dominant assurance smart contract that they or their team owns. If the campaign fails, early pledgers get their full refund along with a portion of the refund bonus (according to a custom formula that can be coded in for each project). If the campaign succeeds, the pledgers get the goods but no bonuses, and the complete refund bonus returns to the campaign owner. This creates a win-win situation for early pledgers, who either get a return on their pledge or get the desired good if the campaign goal is met. 

Ideally, the early pledger refund bonus formula is a type of exponential decay, but for simplicity’s sake, this repo’s version of the dominant assurance smart contract utilizes a very black-and-white formula of having a maximum number of early pledgers, after which pledgers do not get any refund bonus. After the early pledger maximum is reached (configurable by each campaign creator), if the campaign fails, regular pledgers get a full refund but a smaller bonus or no refund bonus at all. The secret sauce is in finding the right formula for your project that incentivizes early pledgers to raise funds above the 30% threshold very early in the campaign. 

Overall, the transparency and deterministic characteristics of the smart contracts help to minimize pledger risk and encourage wider participation, increasing chances of success. Using the dominant assurance mechanism also sends a message to your potential pledgers that you believe in your project so much that you are willing to put your own money at stake for the success of the project.

### DominantJuice.sol Contract Functionality

- `initialize()`: populates Juicebox `projectID`, `cycleTarget`, `minimumPledgeAmount` and `maxEarlyPledgers` variables, effectively readying the project 
- `depositRefundBonus()`: allows the contract owner to deposit refund bonus and emits a RefundBonusDeposited event.
- `payParams()`: This function gets called through the JB architecture when the project receives a payment. The primary funtionality it offers for DominantJuice is function gating via initialization and `miniumPledgeAmount` requirments. 
- `didPay()`: Can only be called by the project `paymentTerminal`, which calls this function when a payer pledges to the project. For DominantJuice, now acting as the JB Pay Delegate, it calculates if pledger is an early pledger, records amount pledged in a mapping, and adds to `totalAmountPledged`.
- `relayCycleResults()`: This function can be called by anyone. It sets `isCampaignExpired` boolean and the contract's/cycle's fund balance and calculates the `isTargetMet` boolean.
It also emits a `CampaignHasClosed` event.
- `redeemParams()`: This is called from JBSingleTokenPaymentTerminalStore3_1_1 when `recordRedemptionFor()` is called (when a payer redeems their tokens). The calling function is nonReentrant. It extends the JB project DominantJuice to introduce withdrawal function gating. If the dominant assurance cycle has not expired or the caller has already been refunded, this function will not work.
- `didRedeem()`: This is executed in the same call chain as `redeemParams()` but happens much later, after the redemption has actually gone through. In DominantJuice, now acting as the JB Redemption Delegate, it checks if the pledger is an early pledger, and if so, the function calculates the early refund bonus. The refund bonus is sent to the pledger, and an event is emitted.
- `creatorWithdraw()`: checks to see if the caller is the contract owner, if campaign has expired, and if the funding goal has been met. If all three are true, then owner can withdraw some or all of the refund bonus they deposited. (They can also withdraw it to any address they want.) Successful execution emits a creator withdrawal event.
- `Getters()`: 
  - `earlyRefundBonusCalc()`: a getter and function helper that calculates individual refund bonuses depending on how many early pledgers there are when called. 
  - `getBalance()`: gets contract balance. 
  - `getCycleFundingStatus()`: gets `totalAmountPledged`, `percentOfGoal`, an `isTargetMet` boolean, and a `hasCreatorWithdrawnAllFunds` boolean.


<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- PROJECT TECHNICALS -->

## Project Technicals

[Goerli Etherscan Verified Contract Page](https://goerli.etherscan.io/address/0xa9e390e216e072106b989fcc8a41d3858f4daad7#readContract)
<br />
Contract Address: ```0xa9E390E216E072106B989fcc8a41D3858f4dAAd7```

Test Coverage Report coming next commit.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- PROJECT WORKFLOW -->

## Project Workflow:

- Deploy Data Source / Dominant Assurance Escrow Contract AKA DominantJuice.sol using the DeployDominantJuice.s.sol deploy script.
- Launch Juicebox Project
  - Specify the Data Source contract address in a Project Launch script / Juicebox UI.
  - Specify cycle start a day or two out to give time to double check if JB project was set correctly, to initialize the Dominant Assurance contract, and to deposit the refund bonus, since pledgers will not be able to pledge until the refund bonus has been deposited. 
  - Initialize DominantJuice (can even do this in same script as Project Launch)
- Project creator deposits refund bonus into DominantJuice.
- Project Funding Cycle begins
  - Pledgers can pledge funds through the regular Juicebox UI
  - No redemptions, no distributions, and no token transfers for cycle 1.
- As the Funding Cycle nears close and the results become clear, the next cycle's configuration will need to be considered. At present, if the result is coming down to the wire and there isn't time to reconfigure, then the workaround could be running a script that creates a very short "dummy" cycle 2 which doesn't allow any movement of funds for anyone, and so you'd then have a chance to reconfigure for a cycle 3, now that the results are known. Either way, adjust the following parameters in the front end (or more than likely a via a reconfigure script):
  - Failed campaign: change `redemptionRate` to 100%, change `pausePay` to true, change `pauseRedeem` and `pauseBurn` to false
  - Successful campaign: change `pauseDistributions` to false and `pauseRedeem` stays as true.
- After cycle completion, the creator or pledgers or literally anyone can call `relayCycleResults()`, which opens one of the withdraw functions:
  - For failed cycles/campaigns, pledgers can redeem all their tokens via the Juicebox UI, which calls `redeemTokensOf()` on the `JBPayoutRedemptionTerminal`, which calls `didRedeem()` in DominantJuice (the JB Redemption Delegate here), which sends the early pledger a refund bonus if applicable. 
  - For successful cycles/campaigns, the project creator can call `creatorWithdraw()` on the DominantJuice contract to receive the funds they deposited at the beginning. 
- The Dominant Assurance DominantJuice contract has fulfilled its duties.
- Creator can withdraw the campaign funds from the JB front end.

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

- Make refund bonus formula more customizable
- Accepting payments in tokens other than ETH.
- In a failed campaign, if pledgers forget to withdraw their refund bonus or lose their keys to their address, add functionality to retrieve their funds and somehow get
them back to them. Could make the function only callable a week after the `campaignExpiryDate` to instill confidence that owner will not abuse the responsibility.
- Add more getter functions like totalAmountRefunded, etc.  


<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LESSONS LEARNED -->

## Lessons Learned

- Things are never permanently stuck. Sometimes all it takes is a good night's sleep, and the answer presents itself in the morning.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->

## Contributing

Scott Auriat was the main consultant and sounding board for this project. And thanks to electrone for help on the front end at the last minute!

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

Thanks to Scott Auriat for his consultation on different aspects, as well as introducing me to the dominant assurance strategy.

A big thanks to the Juicebox devs for prompt, solid AF assistance and guidance.

<p align="right">(<a href="#readme-top">back to top</a>)</p>
