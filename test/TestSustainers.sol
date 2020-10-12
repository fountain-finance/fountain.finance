pragma solidity >=0.4.25 <0.8.0;

import "../contracts/Sustainers.sol";

contract TestSustainers {
    function testInitialBalanceUsingDeployedContract() public {
        Sustainers sustainers = Sustainers();

        uint256 expected = 10000;
        sustainers.updateNeed(10000)

        Assert.equal(
            meta.getNeed(msg.sender),
            expected,
            "Owner should have 10000 MetaCoin initially"
        );
    }

    // function testInitialBalanceWithNewMetaCoin() public {
    //     MetaCoin meta = new MetaCoin();

    //     uint256 expected = 10000;

    //     Assert.equal(
    //         meta.getBalance(tx.origin),
    //         expected,
    //         "Owner should have 10000 MetaCoin initially"
    //     );
    // }
}
