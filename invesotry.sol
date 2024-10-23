// SPDX-License-Identifier: MIT

pragma solidity ^ 0.8 .0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";

contract PropertyInvestor is ERC1155, Ownable, IERC1155Receiver {
    //Uint
    uint256 private poolCount;
    uint256 private propertyCount;
    event PropertyUpdated(
        uint256 indexed propertyId,
        address indexed owner,
        string ipfsURI,
        uint256 associatedPoolId
    );

    //Struct
    struct InvestmentPool {
        uint256 id;
        uint256 numberOfLots;
        uint256 remainingLots;
        uint256 lotPrice;
        uint256 totalInvestment;
        uint256 minLots;
        uint256 investmentstartTime;
        uint256 investmentTimelimit;
        string ipfsURI;
        address[] investors;
        mapping(address => uint256) investments;
        mapping(uint256 => address[]) poolInvestors;
        mapping(uint256 => uint256[]) poolPropertyIds;
        bool poolStatus;
    }
    struct OwnershipDetails {
        address previousOwner;
        address currentOwner;
        uint256 previousPrice;
        uint256 currentPrice;
        uint256 numberOfOwned;
    }
    struct Property {
        uint256 id;
        address owner;
        bool isPropertyVerified;
        string ipfsURI;
        uint256 associatedPoolId;
        address[] propertyInvestors;
    }
    struct Refund {
        address investor;
        uint256 refundAmount;
    }
    struct User {
        address userAddress;
        bool isVerified;
        uint256 kycVerificationTime;
    }

    //Mapping
    mapping(uint256 => uint256) public initallotprice;
    mapping(uint256 => InvestmentPool) private investmentPools;
    mapping(uint256 => Property) private properties;
    mapping(uint256 => Refund[]) public poolRefunds;
    mapping(address => uint256) public balance;
    mapping(uint256 => uint256) public nftPropId;
    mapping(uint256 => string) private ipfsPropDoc;
    mapping(address => User) private users;
    mapping(address => bool) private pennyTransactionConfirmed;
    mapping(address => uint256) private investorToPropertyId;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => OwnershipDetails)))
    private ownershipDetails;

    //Events
    event InvestmentMade(uint256 poolId, address investor, uint256 amount);
    event KYCVerified(address userAddress);
    event PennyTransactionConfirmed(address investor, bool confirmed);
    event PropertyPosted(
        uint256 propertyId,
        address owner,
        string ipfsURI,
        uint256 associatedPoolId
    );
    event PropertyVerified(uint256 propertyId);

    //Constructor
    constructor(string memory _uri) ERC1155(_uri) Ownable(msg.sender) {}

    //User
    function investInPool(
        uint256 _poolId,
        uint256 _lots,
        address _investoraddress
    ) public {
        InvestmentPool storage pool = investmentPools[_poolId];
        require(
            pennyTransactionConfirmed[_investoraddress],
            "Penny transaction must be confirmed by admin"
        );
        require(
            _lots >= pool.minLots && _lots <= pool.remainingLots,
            "Invalid lot count"
        );
        if (!isInvestorInPool(pool, _investoraddress)) {
            pool.investors.push(_investoraddress);
        }
        uint256 investmentAmount = pool.lotPrice * _lots;
        pool.investments[_investoraddress] += investmentAmount;
        pool.totalInvestment += investmentAmount;
        pool.remainingLots -= _lots;
        if (pool.remainingLots == 0) {
            pool.poolStatus = false;
        }
    }

    function postProperty(
        uint256 _associatedPoolId,
        uint256 _poolPropertyId,
        string memory _ipfsURI
    ) public {
        require(users[msg.sender].isVerified, "User must be verified");

        // Check if the property already exists
        if (properties[_poolPropertyId].id != 0) {
            // Assuming property ID starts from 1
            // Property exists, update only the parameters that are provided
            Property storage existingProperty = properties[_poolPropertyId];

            // Update the IPFS URI if it's different
            if (
                keccak256(abi.encodePacked(existingProperty.ipfsURI)) !=
                keccak256(abi.encodePacked(_ipfsURI))
            ) {
                existingProperty.ipfsURI = _ipfsURI;
            }

            // Update associated pool ID if different
            if (existingProperty.associatedPoolId != _associatedPoolId) {
                existingProperty.associatedPoolId = _associatedPoolId;
            }

            emit PropertyUpdated(
                _poolPropertyId,
                msg.sender,
                _ipfsURI,
                _associatedPoolId
            );
        } else {
            // Property does not exist, create a new one
            properties[_poolPropertyId] = Property({
                id: _poolPropertyId,
                owner: msg.sender,
                isPropertyVerified: false,
                ipfsURI: _ipfsURI,
                associatedPoolId: _associatedPoolId,
                propertyInvestors: new address[](0)
            });

            InvestmentPool storage pool = investmentPools[_associatedPoolId];
            pool.poolPropertyIds[_associatedPoolId].push(_poolPropertyId);

            emit PropertyPosted(
                _poolPropertyId,
                msg.sender,
                _ipfsURI,
                _associatedPoolId
            );
        }
    }

    function tradeLots(
        uint256 _poolId,
        uint256 _propertyId,
        uint256 _lots,
        address _to,
        uint256 _currentPrice
    ) public {
        require(_lots > 0, "Must transfer at least one lot");
        uint256 _propertyid = nftPropId[_propertyId];
        for (uint256 i = 0; i < _lots; i++) {
            _transferLot(_propertyid, _to);
            _updateOwnershipDetails(
                _poolId,
                _propertyId,
                _lots,
                _to,
                _currentPrice
            );
        }
    }

    function updatePostPropertyOwnershipDetails(
        uint256 _associatedPoolId,
        uint256 _postedPropertyId,
        uint256 _start,
        uint256 _end
    ) public {
        require(_start < _end, "Invalid range");
        uint256 totalLots = investmentPools[_associatedPoolId].numberOfLots;
        require(_end <= totalLots, "End index exceeds total lots");
        require(
            msg.sender == properties[_postedPropertyId].owner,
            "Only the property owner can update ownership"
        );
        uint256 lotPrice = investmentPools[_associatedPoolId].lotPrice;
        for (uint256 i = _start; i <= _end; i++) {
            ownershipDetails[_associatedPoolId][_postedPropertyId][
                i
            ] = OwnershipDetails({
                previousOwner: address(0),
                currentOwner: msg.sender,
                previousPrice: 0,
                currentPrice: lotPrice,
                numberOfOwned: 0
            });
        }
    }

    //View
    function getInvestmentPoolWithProperties(uint256 _poolId)
    public
    view
    returns(
        uint256 id,
        uint256 numberOfLots,
        uint256 remainingLots,
        uint256 lotPrice,
        uint256 totalInvestment,
        uint256 minLots,
        uint256 investmentstartTime,
        uint256 investmentTimelimit,
        string memory ipfsURI,
        address[] memory investors,
        bool poolStatus,
        uint256[] memory propertyIds
    ) {
        InvestmentPool storage pool = investmentPools[_poolId];
        propertyIds = pool.poolPropertyIds[_poolId];
        return (
            pool.id,
            pool.numberOfLots,
            pool.remainingLots,
            pool.lotPrice,
            pool.totalInvestment,
            pool.minLots,
            pool.investmentstartTime,
            pool.investmentTimelimit,
            pool.ipfsURI,
            pool.investors,
            pool.poolStatus,
            propertyIds
        );
    }

    function getInvestmentPoolIPFSURI(uint256 _poolId)
    public
    view
    returns(string memory) {
        return investmentPools[_poolId].ipfsURI;
    }

    function getInvestorLots(uint256 _poolId, address _investor)
    public
    view
    returns(uint256 lotsOwned, uint256 totalInvestment) {
        InvestmentPool storage pool = investmentPools[_poolId];
        uint256 lots = pool.investments[_investor] / pool.lotPrice;
        uint256 investment = pool.investments[_investor];
        return (lots, investment);
    }

    function getInvestorToPropertyId(address _investor)
    public
    view
    returns(uint256) {
        return investorToPropertyId[_investor];
    }

    function getOwnershipDetails(
        uint256 _poolId,
        uint256 _propertyId,
        uint256 _lotId
    )
    public
    view
    returns(
        address previousOwner,
        address currentOwner,
        uint256 previousPrice,
        uint256 currentPrice,
        uint256 numberOfOwned
    ) {
        OwnershipDetails storage details = ownershipDetails[_poolId][
            _propertyId
        ][_lotId];
        return (
            details.previousOwner,
            details.currentOwner,
            details.previousPrice,
            details.currentPrice,
            details.numberOfOwned
        );
    }

    function getPoolCount() public view returns(uint256) {
        return poolCount;
    }

    function getPropertiesByPool(uint256 _associatedPoolId)
    public
    view
    returns(
        uint256[] memory ids,
        address[] memory owners,
        bool[] memory isPropertyVerified,
        string[] memory ipfsURIs,
        uint256[] memory associatedPoolIds,
        address[][] memory propertyInvestors
    ) {
        uint256 poolPropertyCount = propertyCount;
        Property[] memory poolProperties = new Property[](_associatedPoolId);
        uint256 counter = 0;
        for (uint256 i = 1; i <= poolPropertyCount; i++) {
            if (properties[i].associatedPoolId == _associatedPoolId) {
                poolProperties[counter] = properties[i];
                counter++;
            }
        }
        ids = new uint256[](counter);
        owners = new address[](counter);
        isPropertyVerified = new bool[](counter);
        ipfsURIs = new string[](counter);
        associatedPoolIds = new uint256[](counter);
        propertyInvestors = new address[][](counter);
        for (uint256 j = 0; j < counter; j++) {
            ids[j] = poolProperties[j].id;
            owners[j] = poolProperties[j].owner;
            isPropertyVerified[j] = poolProperties[j].isPropertyVerified;
            ipfsURIs[j] = poolProperties[j].ipfsURI;
            associatedPoolIds[j] = poolProperties[j].associatedPoolId;
            propertyInvestors[j] = poolProperties[j].propertyInvestors;
        }
        return (
            ids,
            owners,
            isPropertyVerified,
            ipfsURIs,
            associatedPoolIds,
            propertyInvestors
        );
    }

    function getProperty(uint256 _propertyId)
    public
    view
    returns(Property memory) {
        return properties[_propertyId];
    }

    function getPropertyCount() public view returns(uint256) {
        return propertyCount;
    }

    function getPropertyInvestmentDetails(uint256 _propertyId)
    public
    view
    returns(
        uint256 id,
        address owner,
        bool isPropertyVerified,
        string memory ipfsURI,
        uint256 associatedPoolId,
        address[] memory propertyInvestors
    ) {
        Property storage property = properties[_propertyId];
        require(property.id != 0, "Property does not exist");
        return (
            property.id,
            property.owner,
            property.isPropertyVerified,
            property.ipfsURI,
            property.associatedPoolId,
            property.propertyInvestors
        );
    }

    function getPropertyIPFSURI(uint256 _propertyId)
    public
    view
    returns(string memory) {
        require(
            properties[_propertyId].owner != address(0),
            "Property does not exist"
        );
        return properties[_propertyId].ipfsURI;
    }

    function getPropertyIPFSURL(uint256 _propertyId)
    public
    view
    returns(string memory) {
        Property storage property = properties[_propertyId];
        require(property.id != 0, "Property does not exist");

        InvestmentPool storage pool = investmentPools[
            property.associatedPoolId
        ];
        require(
            isInvestorInPool(pool, msg.sender),
            "Caller is not an investor in this pool"
        );

        return ipfsPropDoc[_propertyId];
    }

    function getUser(address _userAddress) public view returns(User memory) {
        return users[_userAddress];
    }

    function getUserDetails(address _user)
    public
    view
    returns(bool isVerified, uint256 kycVerificationTime) {
        User storage user = users[_user];
        require(user.userAddress != address(0), "User does not exist");
        return (user.isVerified, user.kycVerificationTime);
    }

    //Internal
    function isInvestorInPool(InvestmentPool storage pool, address investor)
    internal
    view
    returns(bool) {
        for (uint256 i = 0; i < pool.investors.length; i++) {
            if (pool.investors[i] == investor) {
                return true;
            }
        }
        return false;
    }

    function isInvestorInProperty(Property storage property, address investor)
    internal
    view
    returns(bool) {
        for (uint256 i = 0; i < property.propertyInvestors.length; i++) {
            if (property.propertyInvestors[i] == investor) {
                return true;
            }
        }
        return false;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure override returns(bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure override returns(bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function _transferLot(uint256 _propertyId, address _to) internal {
        _safeTransferFrom(msg.sender, _to, _propertyId, 1, "");
    }

    function _updateOwnershipDetails(
        uint256 _poolId,
        uint256 _propertyId,
        uint256 _lots,
        address _to,
        uint256 _currentPrice
    ) internal {
        OwnershipDetails storage details = ownershipDetails[_poolId][
            _propertyId
        ][_lots];
        details.previousOwner = msg.sender;
        details.currentOwner = _to;
        details.previousPrice = details.currentPrice;
        details.currentPrice = _currentPrice;
        details.numberOfOwned += 1;
    }

    function verifyProperty(uint256 _propertyId) internal {
        properties[_propertyId].isPropertyVerified = true;
        emit PropertyVerified(_propertyId);
    }

    //Admin
    function addAdminamount(uint256 _poolId, uint256 _additionalAmount)
    public
    onlyOwner {
        InvestmentPool storage pool = investmentPools[_poolId];
        uint256 requiredLots = _additionalAmount / pool.lotPrice;
        if (pool.remainingLots < requiredLots) {
            uint256 newLots = requiredLots - pool.remainingLots;
            pool.numberOfLots += newLots;
            pool.remainingLots += newLots;
            pool.totalInvestment += newLots * pool.lotPrice;
        }
        if (block.timestamp > pool.investmentTimelimit) {
            pool.investmentTimelimit = block.timestamp;
        }
        if (!isInvestorInPool(pool, msg.sender)) {
            pool.investors.push(msg.sender);
        }
        uint256 investmentAmount = pool.lotPrice * pool.remainingLots;
        pool.investments[msg.sender] += investmentAmount;
        pool.totalInvestment += investmentAmount;
        pool.remainingLots -= requiredLots;
        if (pool.remainingLots == 0) {
            pool.poolStatus = false;
        }
        emit InvestmentMade(_poolId, msg.sender, investmentAmount);
    }

    function confirmPennyTransaction(address _investor) public onlyOwner {
        require(users[_investor].isVerified = true, "complete your kyc");
        pennyTransactionConfirmed[_investor] = true;
        emit PennyTransactionConfirmed(_investor, true);
    }

    function createInvestmentPool(
        uint256 _poolId,
        uint256 _numberOfLots,
        uint256 _lotPrice,
        uint256 _minLots,
        uint256 _investmentstarttime,
        uint256 _investmentTimelimit,
        string memory _ipfsURI
    ) public onlyOwner {
        require(_numberOfLots >= _minLots, "Less number of lots");
        poolCount++;
        InvestmentPool storage newPool = investmentPools[_poolId];
        newPool.id = _poolId;
        newPool.numberOfLots = _numberOfLots;
        newPool.remainingLots = _numberOfLots;
        newPool.lotPrice = _lotPrice;
        initallotprice[_poolId] = _lotPrice;
        newPool.totalInvestment = 0;
        newPool.minLots = _minLots;
        newPool.investmentstartTime = _investmentstarttime;
        newPool.investmentTimelimit = _investmentTimelimit;
        newPool.ipfsURI = _ipfsURI;
        newPool.investors = new address[](0);
        newPool.poolStatus = true;
        users[msg.sender].isVerified = true;
        _mint(address(this), _poolId, _numberOfLots, "");
        emit InvestmentMade(_poolId, address(0), 0);
    }

    function extendInvestmentTime(uint256 _poolId, uint256 _newtimelimit)
    public
    onlyOwner {
        InvestmentPool storage pool = investmentPools[_poolId];
        pool.investmentTimelimit = _newtimelimit;
    }


    function finalizeLots(
        uint256 _poolId,
        uint256 _propertyId,
        uint256 _propertyPrice,
        string memory _ipfsPropDoc
    ) external onlyOwner {
        InvestmentPool storage pool = investmentPools[_poolId];
        Property storage property = properties[_propertyId];
        require(
            property.associatedPoolId == _poolId,
            "Property not associated with this pool"
        );
        require(
            pool.numberOfLots == (pool.totalInvestment / pool.lotPrice),
            "Lots not fully sold yet"
        );
        require(pool.remainingLots == 0, "Pool is not fully invested yet");
        require(
            _propertyPrice == pool.totalInvestment,
            "Amount does not match with property price"
        );
        uint256 totalInvestors = pool.investors.length;
        for (uint256 i = 0; i < totalInvestors; i++) {
            address investor = pool.investors[i];
            uint256 investorLots = pool.investments[investor] / pool.lotPrice;
            require(
                balanceOf(address(this), _poolId) >= investorLots,
                "Insufficient lots in the contract"
            );
            for (uint256 j = 0; j < investorLots; j++) {
                _safeTransferFrom(address(this), investor, _poolId, 1, "");
                OwnershipDetails storage details = ownershipDetails[_poolId][
                    _propertyId
                ][j];
                details.previousOwner = details.currentOwner;
                details.previousPrice = details.currentPrice;
                details.currentOwner = investor;
                details.numberOfOwned++;
                if (!isInvestorInProperty(property, investor)) {
                    property.propertyInvestors.push(investor);
                    investorToPropertyId[investor] = _propertyId;
                }
            }
            pool.poolInvestors[_propertyId].push(investor);
        }
        pool.poolStatus = false;
        ipfsPropDoc[_propertyId] = _ipfsPropDoc;
        propertyCount++;
        nftPropId[_propertyId] = _poolId;
    }

    function updateOwnershipDetails(
        uint256 _poolId,
        uint256 _propertyId,
        address investor,
        uint256 investorLots
    ) internal {
        for (uint256 j = 0; j < investorLots; j++) {
            OwnershipDetails storage details = ownershipDetails[_poolId][
                _propertyId
            ][j];
            details.previousOwner = details.currentOwner;
            details.previousPrice = details.currentPrice;
            details.currentOwner = investor;
            details.numberOfOwned++;
        }
    }

    function finalizeLots(
    uint256 _poolId,
    uint256 _propertyId,
    uint256 _propertyPrice,
    string memory _ipfsPropDoc,
    uint256 startInvestorIndex,
    uint256 endInvestorIndex
) external onlyOwner {
    InvestmentPool storage pool = investmentPools[_poolId];
    Property storage property = properties[_propertyId];
    require(property.associatedPoolId == _poolId, "Property not associated with this pool");
    require(pool.numberOfLots == (pool.totalInvestment / pool.lotPrice), "Lots not fully sold yet");
    require(pool.remainingLots == 0, "Pool is not fully invested yet");
    require(_propertyPrice == pool.totalInvestment, "Amount does not match with property price");

    uint256 totalInvestors = pool.investors.length;

    // Track the total lots needed within the current batch
    uint256 lotsNeeded = 0;

    // First, calculate if there are enough tokens for this batch
    for (uint256 i = startInvestorIndex; i <= endInvestorIndex; i++) {
        if (i >= totalInvestors) {
            break; // Exit if we exceed the total number of investors
        }
        address investor = pool.investors[i];
        uint256 investorLots = pool.investments[investor] / pool.lotPrice;
        lotsNeeded += investorLots;
    }

    // Check if the contract has enough tokens for the required lots
    require(balanceOf(address(this), _poolId) >= lotsNeeded, "Insufficient lots in the contract for this batch");

    // If enough tokens are available, process the transfers
    for (uint256 i = startInvestorIndex; i <= endInvestorIndex; i++) {
        if (i >= totalInvestors) {
            break; // Exit if we exceed the total number of investors
        }
        address investor = pool.investors[i];
        uint256 investorLots = pool.investments[investor] / pool.lotPrice;

        // Transfer lots to the investor
        for (uint256 j = 0; j < investorLots; j++) {
            _safeTransferFrom(address(this), investor, _poolId, j, "");
            OwnershipDetails storage details = ownershipDetails[_poolId][_propertyId][j];
            details.previousOwner = details.currentOwner;
            details.previousPrice = details.currentPrice;
            details.currentOwner = investor;
            details.numberOfOwned++;
            if (!isInvestorInProperty(property, investor)) {
                property.propertyInvestors.push(investor);
                investorToPropertyId[investor] = _propertyId;
            }
        }
        pool.poolInvestors[_propertyId].push(investor);
    }

    // If all investors have been processed, update the pool status and finalize
    if (endInvestorIndex >= totalInvestors - 1) {
        pool.poolStatus = false;
        ipfsPropDoc[_propertyId] = _ipfsPropDoc;
        propertyCount++;
        nftPropId[_propertyId] = _poolId;
    }
}


    function increaseNumberOfLots(uint256 _poolId, uint256 _additionalLots)
    public
    onlyOwner {
        InvestmentPool storage pool = investmentPools[_poolId];
        require(_additionalLots > 0, "Must add more than zero lots");
        pool.numberOfLots += _additionalLots;
        pool.remainingLots += _additionalLots;
        _mint(address(this), _poolId, _additionalLots, "");
        emit InvestmentMade(
            _poolId,
            address(0),
            _additionalLots * pool.lotPrice
        );
    }

    function refundTotalInvestment(uint256 _poolId) public onlyOwner {
        InvestmentPool storage pool = investmentPools[_poolId];
        require(pool.poolStatus == true, "pool id is not valid");
        for (uint256 i = 0; i < pool.investors.length; i++) {
            address investor = pool.investors[i];
            uint256 investmentAmount = pool.investments[investor];
            balance[investor] += investmentAmount;
            pool.totalInvestment -= investmentAmount;
            pool.investments[investor] -= investmentAmount;
        }
        pool.poolStatus = false;
    }

    function setInvestmentPool(
        uint256 _poolId,
        uint256 _numberOfLots,
        uint256 _remainingLots,
        uint256 _lotPrice,
        uint256 _totalInvestment,
        uint256 _minLots,
        uint256 _investmentTimelimit,
        string memory _ipfsURI,
        bool _poolStatus
    ) public onlyOwner {
        InvestmentPool storage pool = investmentPools[_poolId];
        pool.id = _poolId;
        pool.numberOfLots = _numberOfLots;
        pool.remainingLots = _remainingLots;
        pool.lotPrice = _lotPrice;
        pool.totalInvestment = _totalInvestment;
        pool.minLots = _minLots;
        pool.investmentstartTime = block.timestamp;
        pool.investmentTimelimit = _investmentTimelimit;
        pool.ipfsURI = _ipfsURI;
        pool.poolStatus = _poolStatus;
    }

    function setInvestorToPropertyId(address _investor, uint256 _propertyId)
    public
    onlyOwner {
        investorToPropertyId[_investor] = _propertyId;
    }

    function setPoolCount(uint256 _newPoolCount) public onlyOwner {
        poolCount = _newPoolCount;
    }

    function setProperty(
        uint256 _propertyId,
        address _owner,
        bool _isPropertyVerified,
        string memory _ipfsURI,
        uint256 _associatedPoolId
    ) public onlyOwner {
        properties[_propertyId] = Property({
            id: _propertyId,
            owner: _owner,
            isPropertyVerified: _isPropertyVerified,
            ipfsURI: _ipfsURI,
            associatedPoolId: _associatedPoolId,
            propertyInvestors: new address[](0)
        });
    }

    function setPropertyCount(uint256 _newPropertyCount) public onlyOwner {
        propertyCount = _newPropertyCount;
    }

    function setOwnershipDetails(
        uint256 _poolId,
        uint256 _propertyId,
        uint256 _lotId,
        address _previousOwner,
        address _currentOwner,
        uint256 _previousPrice,
        uint256 _currentPrice,
        uint256 _numberOfOwned
    ) public onlyOwner {
        OwnershipDetails storage details = ownershipDetails[_poolId][
            _propertyId
        ][_lotId];
        details.previousOwner = _previousOwner;
        details.currentOwner = _currentOwner;
        details.previousPrice = _previousPrice;
        details.currentPrice = _currentPrice;
        details.numberOfOwned = _numberOfOwned;
    }

    function setUser(
        address _userAddress,
        bool _isVerified,
        uint256 _kycVerificationTime
    ) public onlyOwner {
        User storage user = users[_userAddress];
        user.userAddress = _userAddress;
        user.isVerified = _isVerified;
        user.kycVerificationTime = _kycVerificationTime;
    }

    function surplusRefundcalculate(uint256 _poolId, uint256 _propertyPrice)
    internal
    onlyOwner {
        InvestmentPool storage pool = investmentPools[_poolId];
        require(
            pool.totalInvestment > _propertyPrice,
            "Total investment is less than the property price"
        );
        uint256 totalSurplus = pool.totalInvestment - _propertyPrice;
        uint256 surplusPerLot = totalSurplus / pool.numberOfLots;
        delete poolRefunds[_poolId];
        for (uint256 i = 0; i < pool.investors.length; i++) {
            address investor = pool.investors[i];
            uint256 investorLots = pool.investments[investor] / pool.lotPrice;
            uint256 investorSurplus = surplusPerLot * investorLots;
            pool.investments[investor] -= investorSurplus;
            poolRefunds[_poolId].push(Refund(investor, investorSurplus));
        }
        pool.totalInvestment -= totalSurplus;
        pool.lotPrice = _propertyPrice / pool.numberOfLots;
    }

    function updatesurplusrefund(uint256 _poolId) public onlyOwner {
        InvestmentPool storage pool = investmentPools[_poolId];
        uint256 totalSurplus = pool.numberOfLots *
            initallotprice[_poolId] -
            pool.totalInvestment;
        uint256 surplusPerLotprice = totalSurplus / pool.numberOfLots;
        for (uint256 i = 0; i < pool.investors.length; i++) {
            address investor = pool.investors[i];
            uint256 investorLots = pool.investments[investor] / pool.lotPrice;
            uint256 investorSurplus = surplusPerLotprice * investorLots;
            balance[investor] += investorSurplus;
            pool.investments[investor] -= investorSurplus;
            poolRefunds[_poolId].push(Refund(investor, investorSurplus));
        }
    }

    function surplusRefund(uint256 _poolId, uint256 _propertyPrice)
    public
    onlyOwner {
        InvestmentPool storage pool = investmentPools[_poolId];
        require(
            pool.totalInvestment > _propertyPrice,
            "Total investment is less than the property price"
        );
        uint256 totalSurplus = pool.totalInvestment - _propertyPrice;
        uint256 surplusPerLot = totalSurplus / pool.numberOfLots;
        delete poolRefunds[_poolId];
        for (uint256 i = 0; i < pool.investors.length; i++) {
            address investor = pool.investors[i];
            uint256 investorLots = pool.investments[investor] / pool.lotPrice;
            uint256 investorSurplus = surplusPerLot * investorLots;
            balance[investor] += investorSurplus;
            pool.investments[investor] -= investorSurplus;
            poolRefunds[_poolId].push(Refund(investor, investorSurplus));
        }
        pool.totalInvestment -= totalSurplus;
        pool.lotPrice = _propertyPrice / pool.numberOfLots;
    }

    function verifyKYC(address _user, bool _st) public onlyOwner {
        users[_user] = User({
            userAddress: _user,
            isVerified: _st,
            kycVerificationTime: block.timestamp
        });
        emit KYCVerified(_user);
    }
}