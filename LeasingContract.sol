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
    bool _paydayConstraintEnabled;

    mapping(uint => Contract) _contracts;
    mapping(uint => Agreement) _agreements;
    mapping(uint => Transfer) _transfers;

    event ContractCreated(uint id);
    event PaidTolandlord(uint id, uint amount, uint depositRemaining);

    event CallFinishedWithResult(bool);
    event DepositAdded(uint added, uint totalDeposit, address sender);

    event ShowedStatusMessage(string);
    event ShowedStatusMessage(uint);
    event ShowedStatusMessage(bool);

    function LeasingContract() public {
        _owner = msg.sender;
        _counter = 0;
        _paydayConstraintEnabled = true;
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
        ShowedStatusMessage(_agreements[id].lastUpdate + 1 days);
        require(!_paydayConstraintEnabled);
        require(_agreements[id].lastUpdate + 1 days >= now);
        _;
    }

    function() public payable {}

    function createContract(uint fee, uint deposit, uint dayPenalty)
    public
    {
        _contracts[_counter] = Contract(_counter, msg.sender, fee, deposit, dayPenalty);
        _agreements[_counter] = Agreement(_counter, 0x0, 0, 0, 0);

        ContractCreated(_counter);
        _counter += 1;

        ShowedStatusMessage("El contrato ha sido creado");
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

    function getAgreement(uint id) public constant
    returns (uint _id, address _leasee, uint _deposit, uint _pending, uint _lastUpdate)
    {
        Agreement memory agreement = _agreements[id];
        _id = agreement.contractId;
        _leasee = agreement.leasee;
        _deposit = agreement.deposit;
        _pending = agreement.pending;
        _lastUpdate = agreement.lastUpdate;
    }

    function getTransfer(uint id) public constant
    returns (uint _id, address _aspirant, bool _landlord, bool _leasee, uint _deposit)
    {
        Transfer memory transfer = _transfers[id];
        _id = transfer.contractId;
        _aspirant = transfer.aspirant;
        _landlord = transfer.landlord;
        _leasee = transfer.leasee;
        _deposit = transfer.deposit;
    }

    function agreeContract(uint id) public payable
        contactInactive(id)
    {
        Contract storage contrakt = _contracts[id];
        uint required = contrakt.requiredDeposit + contrakt.pricePerDay;

        if (weiToEther(msg.value) < required) {
            CallFinishedWithResult(false);
            ShowedStatusMessage("No se ha podido confirmar el acuerdo por falta de fondos");
        }
        require(weiToEther(msg.value) >= required);

        _agreements[id] = Agreement(id, msg.sender, weiToEther(msg.value) - contrakt.pricePerDay, 0, now);
        contrakt.landlord.transfer(etherToWei(contrakt.pricePerDay));
        CallFinishedWithResult(true);

        ShowedStatusMessage("El arrendatario ha aceptado las condiciones del contrato");

    }

    function topUpDeposit(uint id)
    public payable
        contractActive(id)
    {
        _agreements[id].deposit += weiToEther(msg.value);
        DepositAdded(msg.value, _agreements[id].deposit, msg.sender);
    }

    function payday(uint id) public payable
        dayElapsed(id)
    {
        Contract storage contrakt = _contracts[id];
        Agreement storage agreement = _agreements[id];

        uint amount = contrakt.pricePerDay + (agreement.pending * contrakt.dayPenalty);

        if (agreement.deposit >= amount) {
            contrakt.landlord.transfer(etherToWei(amount));
            agreement.deposit -= amount;
            agreement.pending = 0;

            PaidTolandlord(id, amount, agreement.deposit);
            ShowedStatusMessage("El pago ha sido realizado correctamente");
        } else {
            agreement.pending += 1;

            CallFinishedWithResult(false);
            ShowedStatusMessage("El arrendatario no tiene fondos suficientes, se ha aplicado un recargo");
        }

        agreement.lastUpdate = now;
    }

    function nominateForTransfer(uint id, address aspirant) public payable
        contractActive(id)
        landlordOrLeasee(id)
    {
        Transfer storage transfer = _transfers[id];
        transfer.contractId = id;

        Contract storage contrakt = _contracts[id];
        Agreement storage agreement = _agreements[id];

        if (msg.sender == contrakt.landlord && (transfer.aspirant == 0x0 || transfer.aspirant == aspirant)) {
            transfer.landlord = true;
            transfer.aspirant = aspirant;
            ShowedStatusMessage("El arrendador ha aceptado el acuerdo de transferencia");
        } else if (msg.sender == agreement.leasee && (transfer.aspirant == 0x0 || transfer.aspirant == aspirant)) {
            transfer.leasee = true;
            transfer.aspirant = aspirant;
            ShowedStatusMessage("El arrendatario ha aceptado el acuerdo de transferencia");
        }
        if (transfer.landlord && transfer.leasee) {
            CallFinishedWithResult(true);
            return;
        }
        CallFinishedWithResult(false);
    }

    function acceptTransfer(uint id) public payable
        contractActive(id)
        onlyAspirant(id)
    {
        Contract storage contrakt = _contracts[id];
        Agreement storage agreement = _agreements[id];
        Transfer storage transfer = _transfers[id];

        uint quota = contrakt.pricePerDay + (_agreements[id].pending * contrakt.dayPenalty);

        require(weiToEther(msg.value) >= quota);

        transfer.deposit = weiToEther(msg.value);

        if (transfer.landlord && transfer.leasee) {
            agreement.leasee.transfer(etherToWei(agreement.deposit));
            agreement.leasee = transfer.aspirant;
            agreement.deposit = transfer.deposit;
            delete _transfers[id];

            CallFinishedWithResult(true);
            ShowedStatusMessage("Se ha cambiado el arrendador y se ha devuelto el deposito al antiguo arrendador");
            return;
        }

        CallFinishedWithResult(false);
    }

    function disarmPaydayContraint() public {
        require(msg.sender == _owner);
        _paydayConstraintEnabled = false;
        ShowedStatusMessage("[DEBUG] Se han cambiado las condiciones del contrato");
    }

    function weiToEther(uint weis) internal pure
    returns(uint)
    {
        return weis / (10 ** 18);
    }

    function etherToWei(uint ethers) internal pure
    returns(uint)
    {
        return ethers * (10 ** 18);
    }
}