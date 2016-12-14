pragma solidity ^0.4.4;

/*
    Copyright 2016, Jordi Baylina

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import "MiniMeToken.sol";

contract ApproveAndVote is TokenController {


    modifier onlySelf {
        if (msg.sender != address(this)) throw;
        _;
    }

    function ProposalSelector(
        address _tokenAddress,
        uint _supportTime,
        uint _votingTime,
        uint _percentageToAccept,
        uint _deposit,
        address _collectedDepositsDestination)
    {
        token = MiniMeToken(_tokenAddress);
        supportTime = _supportTime;
        votingTime = _votingTime;
        percentageToAccept = _percentageToAccept;
        deposit = _deposit;
        collectedDepositsDestination = _collectedDepositsDestination;
    }

    enum ProposalStatus { GainingSupport, Voting, Accepted, Rejected }

    struct Proposal {
        uint creationDate;
        address owner;
        uint deposit;

        string title;
        bytes32 swarmHash;
        address recipient;
        uint amount;
        bytes data;

        ProposalStatus status;
        uint closingTime;

        MiniMeToken proposalToken;
        uint totalYes;
        uint totalNo;
        mapping (address => uint) yesVotes;
        mapping (address => uint) noVotes;
    }

    Proposal[] public proposals;

    uint public votingTime = 14 days;
    uint public supportTime = 14 days;
    uint public deposit = 2 ether;
    uint public percentageToAccept = 10**16;   // 10**18 = 100
    MiniMeToken public token;
    address collectedDepositsDestination;

    function newPreproposal(string _title, bytes32 _swarmHash, address _recipient, uint _amount, bytes _data) payable returns (uint) {
        if (msg.value != deposit) throw;
        uint idProposal = proposals.length ++;
        Proposal proposal = proposals[idProposal];


        var (name,symbol) = getTokenNameSymbol(token);
        string memory proposalName = strConcat(name , "_", uint2str(idProposal));
        string memory proposalSymbol = strConcat(symbol, "_", uint2str(idProposal));

        proposal.creationDate = now;
        proposal.owner = msg.sender;
        proposal.title = _title;
        proposal.swarmHash = _swarmHash;
        proposal.recipient = _recipient;
        proposal.amount = _amount;
        proposal.data = _data;
        proposal.closingTime = now + supportTime;
        proposal.proposalToken = MiniMeToken(token.createCloneToken(proposalName, token.decimals(), proposalSymbol, block.number, false));
        proposal.totalYes = 0;
        proposal.totalNo = 0;
        proposal.status = ProposalStatus.GainingSupport;
        proposal.deposit = deposit;

        return idProposal;
    }


    function vote(uint _idProposal, bool _support) {
        if (_idProposal >= proposals.length) throw;
        Proposal proposal = proposals[_idProposal];
        voteAmount(_idProposal, _support, proposal.proposalToken.balanceOf(msg.sender));
    }

    function voteAmount(uint _idProposal, bool _support, uint _amount) {
        if (_amount == 0) return;

        if (_idProposal >= proposals.length) throw;
        Proposal p = proposals[_idProposal];
        if (    (    (p.status != ProposalStatus.GainingSupport)
                  && (p.status != ProposalStatus.Voting))
             || (now > p.closingTime)
             || (token.balanceOf(msg.sender) < _amount))
            throw;

        if (_support) {
            p.totalYes += _amount;
            p.yesVotes[msg.sender] += _amount;
        } else {
            p.totalNo += _amount;
            p.noVotes[msg.sender] += _amount;
        }

        if (!p.proposalToken.transferFrom(msg.sender, this, _amount)) throw;

        if (p.status == ProposalStatus.GainingSupport) {
            uint supportPercentage = (p.totalYes - p.totalNo)*(10**18) / p.proposalToken.totalSupply();
            if ( supportPercentage > percentageToAccept ) {
                p.status = ProposalStatus.Voting;
                p.closingTime = now + votingTime;
            }
        }
    }

    function unvote(uint _idProposal) {
        if (_idProposal >= proposals.length) throw;
        Proposal p = proposals[_idProposal];

        unvoteAmount(_idProposal, true, p.yesVotes[msg.sender]);
        unvoteAmount(_idProposal, false, p.noVotes[msg.sender]);
    }

    function unvoteAmount(uint _idProposal, bool _support, uint _amount) {
        if (_amount == 0) return;

        if (_idProposal >= proposals.length) throw;
        Proposal p = proposals[_idProposal];

        if (    (    (p.status != ProposalStatus.GainingSupport)
                  && (p.status != ProposalStatus.Voting))
             || (now > p.closingTime))
            throw;

        if (_support) {
            if (p.yesVotes[msg.sender] < _amount) throw;
            p.totalYes -= _amount;
            p.yesVotes[msg.sender] -= _amount;
        } else {
            if (p.noVotes[msg.sender] < _amount) throw;
            p.totalNo -= _amount;
            p.noVotes[msg.sender] -= _amount;
        }

        if (!p.proposalToken.transferFrom(this, msg.sender, _amount)) throw;

    }

    function executeProposal(uint _idProposal) {
        if (_idProposal >= proposals.length) throw;
        Proposal p = proposals[_idProposal];

        if (    (    (p.status != ProposalStatus.GainingSupport)
                  && (p.status != ProposalStatus.Voting))
             || (now <= p.closingTime))
            throw;

        if (p.status == ProposalStatus.GainingSupport) {
            p.status = ProposalStatus.Rejected;
            if (!collectedDepositsDestination.send(p.deposit)) throw;
        } else {     // Voting

            if (p.yesVotes > p.noVotes) {
                p.status = ProposalStatus.Accepted;
                if (! p.recipient.call.value(p.amount)(p.data))  throw;
            } else {
                p.status = ProposalStatus.Rejected;
            }
            if (!p.owner.send(p.deposit)) throw;
        }
    }


// Setting functions

    function setVotingTime(uint _newVotingTime) onlySelf {
        votingTime = _newVotingTime;
    }

    function setSupportTime(uint _newSupportTime) onlySelf {
        supportTime = _newSupportTime;
    }

    function setDeposit(uint _newDeposit) onlySelf {
        deposit = _newDeposit;
    }

    function setPercentageToAccept(uint _newPercentageToAccept) onlySelf {
        percentageToAccept = _newPercentageToAccept;
    }

    function setCollectedDepositsDestination(address _newCollectedDepositsDestination) onlySelf {
        collectedDepositsDestination = _newCollectedDepositsDestination;
    }



// Token controller

    function proxyPayment(address _owner) payable returns(bool) {
        return false;
    }

    /// @notice Notifies the controller about a transfer
    /// @param _from The origin of the transfer
    /// @param _to The destination of the transfer
    /// @param _amount The amount of the transfer
    /// @return False if the controller does not authorize the transfer
    function onTransfer(address _from, address _to, uint _amount)
        returns(bool)
    {
        return true;
    }

    /// @notice Notifies the controller about an approval
    /// @param _owner The address that calls `approve()`
    /// @param _spender The spender in the `approve()` call
    /// @param _amount The ammount in the `approve()` call
    /// @return False if the controller does not authorize the approval
    function onApprove(address _owner, address _spender, uint _amount)
        returns(bool)
    {
        return true;
    }


/// Strigng manipulation function

    function strConcat(string _a, string _b, string _c, string _d, string _e) internal returns (string){
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        bytes memory _bc = bytes(_c);
        bytes memory _bd = bytes(_d);
        bytes memory _be = bytes(_e);
        string memory abcde = new string(_ba.length + _bb.length + _bc.length + _bd.length + _be.length);
        bytes memory babcde = bytes(abcde);
        uint k = 0;
        for (uint i = 0; i < _ba.length; i++) babcde[k++] = _ba[i];
        for (i = 0; i < _bb.length; i++) babcde[k++] = _bb[i];
        for (i = 0; i < _bc.length; i++) babcde[k++] = _bc[i];
        for (i = 0; i < _bd.length; i++) babcde[k++] = _bd[i];
        for (i = 0; i < _be.length; i++) babcde[k++] = _be[i];
        return string(babcde);
    }

    function strConcat(string _a, string _b, string _c, string _d) internal returns (string) {
        return strConcat(_a, _b, _c, _d, "");
    }

    function strConcat(string _a, string _b, string _c) internal returns (string) {
        return strConcat(_a, _b, _c, "", "");
    }

    function strConcat(string _a, string _b) internal returns (string) {
        return strConcat(_a, _b, "", "", "");
    }

    function uint2str(uint a) internal returns (string) {
        return bytes32ToString(uintToBytes(a));
    }

    function uintToBytes(uint v) constant returns (bytes32 ret) {
        if (v == 0) {
            ret = '0';
        }
        else {
            while (v > 0) {
                ret = bytes32(uint(ret) / (2 ** 8));
                ret |= bytes32(((v % 10) + 48) * 2 ** (8 * 31));
                v /= 10;
            }
        }
        return ret;
    }

    function bytes32ToString (bytes32 data) constant returns (string) {
        bytes memory bytesString = new bytes(32);
        for (uint j=0; j<32; j++) {
            byte char = byte(bytes32(uint(data) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[j] = char;
            }
        }
        return string(bytesString);
    }

    function getTokenNameSymbol(address tokenAddr) internal returns (string name, string symbol) {
        return (getString(token, sha3("name()")),getString(token, sha3("symbol()")));
    }

    function getString(address _dst, bytes32 sig) internal returns(string) {
        string memory s;

        assembly {
                let x := mload(0x40)   //Find empty storage location using "free memory pointer"
                mstore(x,sig) //Place signature at begining of empty storage

                let success := call(      //This is the critical change (Pop the top stack value)
                                    5000, //5k gas
                                    _dst, //To addr
                                    0,    //No value
                                    x,    //Inputs are stored at location x
                                    0x04, //Inputs are 36 byes long
                                    x,    //Store output over input (saves space)
                                    0x80) //Outputs are 32 bytes long

                let strL := mload(add(x, 0x20))   // Load the length of the sring

                jumpi(ask_more, gt(strL, 64))

                mstore(0x40,add(x,add(strL, 0x40)))

                s := add(x,0x20)
            ask_more:
                mstore(x,sig) //Place signature at begining of empty storage

                let success := call(      //This is the critical change (Pop the top stack value)
                                    5000, //5k gas
                                    _dst, //To addr
                                    0,    //No value
                                    x,    //Inputs are stored at location x
                                    0x04, //Inputs are 36 byes long
                                    x,    //Store output over input (saves space)
                                    add(0x40, strL)) //Outputs are 32 bytes long

                mstore(0x40,add(x,add(strL, 0x40)))
                s := add(x,0x20)

        }

        return s;
    }
}

