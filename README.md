<img src="imgs/fountain.png" alt="Fountain" width="100"/>

#### fountain.finance

###### An experiment in composable fundraising, income streams, surplus redistribution, and sustainable growth on Ethereum.

### Mechanism

1. Define what sustainability means to your project over a specified period of time.
2. Anyone anywhere in the world (or any smart contract) can send funds to help fulfill your sustainability.
3. Any surplus funds get redistributed back to sustainers proportionally.
4. Repeat, updating what sustainability means to you if needed.

### Overview 

Fountain is a smart contract that provides a new internet business model for funding open source internet services, public goods, microfinance, indy projects, and just about any initiative where the cost of execution is periodically recurring and mostly predictable.

The thesis here is that the cost to develop, run, grow, and maintain global-scale software projects has become more and more predictable as we've abstracted and automated away complexity and variability behind cloud computing service providers and Ethereum. Meanwhile Twitter and GitHub allow a project's contributors and its community to exchange ideas and earn one others' trust more collaboratively, authentically, and iteratively. 

Leaning heavily on the contributor <==> community relationship and community-driven growth, there's an opportunity for a mechanism that ensures each valued project's sustainability while pushing each individual community member's price towards zero as more people come on board. The Fountain contract does this by allowing projects to preemptively publish what sustainability means to them for a specified period of time, and redistributing surplus back to community members trustlessly.

Ethereum also makes it easy for other smart contracts to integrate into the Fountain contract's functionality, which makes two neat things possible: 

1. Projects can route their income stream through this contract to create community-driven business models that haven't been possible before. For example you can make a CashApp-like contract that takes **$X** a month to be sustainably run (labor, ops) where every person-to-person transaction incurs a fee **($Y)** that goes towards sustaining the service, but if there are enough transactions that month **(N)** such that **N * $Y > $X**, then for each subsequent transaction, each account who has paid fees during the month receives a dividend from the surplus revenue that is proportional to the amount they've contributed to the project's sustainability thus far. So if **N * $Y** grows unjustifiably faster than **$X** — which is the underlying market rent-seeking inefficiency that this contract tries to outcompete — then instead of compounded shareholder wealth aggregation, everyone's price tends towards zero. Meaning people get a nearly-free, community-driven product with no ads, guaranteed data integrity, full business operation accountability, and an open source code base that runs reliably. All with motivated contributors that are getting paid the fair share that they ask for. 

2. It'll be easy to create sustainability dependencies, so a project's sustainability can be algorithmically hooked up to that of projects it depends on. This mimics an overflowing fountain effect ⛲️ where a water stream directed at a top surface can end up overflowing the pools of each layer beneath, so long as the boundary of each pool is defined ahead of time.  ️ 

### TODO 

This contract still needs to be revised and deployed, and the proposed game theory should be further discussed, critiqued, and tested in production.