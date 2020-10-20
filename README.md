<img src="imgs/fountain.png" alt="Fountain" width="100"/>

#### fountain.finance

###### An experiment in composable fundraising, income streams, surplus redistribution, and sustainable growth on Ethereum.

### Mechanism

1. Define what sustainability means to your project over a specified period of time.
2. Anyone anywhere in the world (or any smart contract) can send funds to help fulfill your sustainability.
3. Any surplus funds get redistributed back to sustainers proportionally.
4. Repeat, updating what sustainability means to you if needed.

### Overview 

Fountain is a new internet business model for funding open source internet services, public goods, microfinance, indy projects, and just about any initiative where the cost of execution is periodically recurring and mostly predictable.

The thesis here is that the cost to develop, run, grow, and maintain global-scale software projects has become more and more predictable as we've abstracted and automated away complexity and variability behind cloud computing service providers and Ethereum. Meanwhile Twitter and GitHub allow a project's contributer and its community to exchange ideas and earn one others' trust more collaboratively, authentically, and iteratively. 

Leaning heavily on the contributer <==> community relationship and community-driven growth, there's an opportunity for a mechanism that ensures each valued project's sustainability while pushing each individual community member's price towards zero as more people come on board. The Fountain contract does this by allowing projects to premptively publish what sustainability means to them for a specified duration, and redistributing surplus back to community members trustlessly.

Ethereum also makes it easy for other smart contracts to integrate into the Fountain contract's functionality, which makes two neat things possible: 

1. Projects can route their income stream through this contract to create community-driven business models that haven't been possible before. For example you can make a CashApp-like contract that costs **X** a month to be sustainable (labor, ops) where every transaction incurs a fee **(Y)** that goes towards sustaining the service, but if there are enough transactions that month **(N)** where **N * Y > X**, then for each subsequent transaction, accounts who have paid fees receive a dividend from the surplus revenue that are proportional to the amount they've each contributed to the project's sustainability thus far. If **N * Y*** grows unjustifiably faster than **X** -- which is the underlying market inefficiency that this contract tries to exploit -- then everyone's price tends towards zero, meaning they get a free product with no ads, guarenteed data integrity, full business operation accountability, and an open source code base that runs reliably, all with motivated contributers and community members. 

2. It'll be easy to create sustainability dependencies, so a project's sustainability can be algorithmically hooked up to that of projects it depends on. This mimics an overflowing fountain effect ⛲️ where a water stream directed at a top surface can end up overflowing the pools of each layer beneath, so long as the boundary of each pool is defined ahead of time.  ️ 

