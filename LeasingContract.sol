pragma solidity ^0.4.17;

contract LeasingContract {
    
    struct Contract {
        uint id;
        address landlord;
        uint pricePerDay;
        uint requiredDeposit;
        uint dayPenalty;
    }
    
    struct Agreement {
        uint contractId;
        address leasee;
        uint deposit;
        uint pending;
        uint lastUpdate;
    }
    
    struct Transfer {
        uint contractId;
        address aspirant;
        bool landlord;
        bool leasee;
        uint deposit;
    }
    
    address _owner;
    uint _counter;
    bool _paydayConstraintEnabled = true;
    
    mapping(uint => Contract) _contracts;
    mapping(uint => Agreement) _agreements;
    mapping(uint => Transfer) _transfers;
    
    event ContractCreated(uint id);
    event PaidTolandlord(uint id, uint amount, uint depositRemaining);

    event CallFinishedWithResult(bool);
    event DepositAdded(uint added, uint totalDeposit, address sender);
    
    function LeasingContract() public {
        _owner = msg.sender;
        _counter = 0;
    }
    
    modifier contractActive(uint id) {
        require(_agreements[id].leasee != 0x0);
        _;
    }
    
    modifier contactInactive(uint id) {
        require(_contracts[id].landlord != 0x0 && _agreements[id].leasee == 0x0);
        _;
    }
    
    modifier landlordOrLeasee(uint id) {
        require(msg.sender == _contracts[id].landlord || msg.sender == _agreements[id].leasee);
        _;
    }
    
    modifier onlyAspirant(uint id) {
        require(msg.sender == _transfers[id].aspirant);
        _;
    }
    
    modifier dayElapsed(uint id) {
        require(!_paydayConstraintEnabled || _agreements[id].lastUpdate + 1 days >= now);
        _;
    }
    
    function() payable {}
    
    function createContract(uint fee, uint deposit, uint dayPenalty)
        public 
    {
        _contracts[_counter] = Contract(_counter, msg.sender, fee, deposit, dayPenalty);
        _agreements[_counter] = Agreement(_counter, 0x0, 0, 0, 0);

        ContractCreated(_counter);
        _counter += 1;
    }
    
    function getContract(uint id) public constant 
        returns (uint _id, address _landlord, uint _pricePerDay, uint _requiredDeposit, uint _dayPenalty) 
    {
        Contract memory contrakt = _contracts[id];
        _id = contrakt.id;
        _landlord = contrakt.landlord;
        _pricePerDay = contrakt.pricePerDay;
        _requiredDeposit = contrakt.requiredDeposit;
        _dayPenalty = contrakt.dayPenalty;
    }

    function agreeContract(uint id) public payable 
        contactInactive(id)
    {
        Contract contrakt = _contracts[id];
        uint required = (contrakt.requiredDeposit + contrakt.pricePerDay) * (10 ** 18);
        
        require(msg.value >= required);

        _agreements[id] = Agreement(id, msg.sender, msg.value - contrakt.pricePerDay, now, 0);
        contrakt.landlord.transfer(contrakt.pricePerDay * (10 ** 18));
        CallFinishedWithResult(true);

    }
    
    function topUpDeposit(uint id)
        public payable 
        contractActive(id)
    {
        _agreements[id].deposit += msg.value;
        DepositAdded(msg.value, _agreements[id].deposit, msg.sender);
    }
    
    function payday(uint id) public payable 
        dayElapsed(id)
    {
        Contract contrakt = _contracts[id];
        Agreement storage agreement = _agreements[id];

        uint amount = contrakt.pricePerDay + (agreement.pending * contrakt.dayPenalty);

        if (agreement.deposit >= amount) {
            contrakt.landlord.transfer(amount * (10 ** 18));
            agreement.deposit -= amount;
            agreement.pending = 0;

            PaidTolandlord(id, amount, agreement.deposit);
        } else {
            agreement.pending += 1;
            
            CallFinishedWithResult(false);
        }

        agreement.lastUpdate = now;
    }
    
    function nominateForTransfer(uint id, address aspirant) public payable 
        contractActive(id) 
        landlordOrLeasee(id)
    {
        Transfer storage transfer = _transfers[id];
        transfer.contractId = id;
        transfer.aspirant = aspirant;

        Contract contrakt = _contracts[id];
        Agreement agreement = _agreements[id];

        if (msg.sender == contrakt.landlord) {
            transfer.landlord = true;
        } else if (msg.sender == agreement.leasee) {
            transfer.leasee = true;
        }

        if (transfer.landlord && transfer.leasee && transfer.deposit > 0) {
            agreement.leasee.transfer(agreement.deposit);
            agreement.leasee = transfer.aspirant;
            agreement.deposit = transfer.deposit;
            delete _transfers[id];

            CallFinishedWithResult(true);
            return;
        } 

        CallFinishedWithResult(false);
    }
    
    function acceptTransfer(uint id) public payable 
        contractActive(id) 
        onlyAspirant(id)
    {
        Contract contrakt = _contracts[id];
        uint quota = contrakt.pricePerDay + (_agreements[id].pending * contrakt.dayPenalty);

        if (msg.value >= quota) {
            _transfers[id].deposit = msg.value;
            CallFinishedWithResult(true);
            return;
        }

        CallFinishedWithResult(false);
    }
    
    function disarmPaydayContraint() public {
        require(msg.sender == _owner);
        _paydayConstraintEnabled = false;
    }
}