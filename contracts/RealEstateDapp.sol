// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract RealEstateDapp is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _totalApts;

    struct AptStruct {
        uint id;
        string name;
        string desc;
        string loc;
        string images;
        uint rooms;
        uint price;
        address owner;
        bool booked;
        bool deleted;
        uint timestamp;
    }

    struct BookingStruct {
        uint id;
        uint aptid;
        address tenant;
        uint date;
        uint price;
        bool checked;
        bool cancelled;
    }

    struct ReviewStruct {
        uint id;
        uint aptid;
        string text;
        uint timestamp;
        address owner;
    }

    uint public securityFee;
    uint public tax;

    constructor(uint _tax, uint _securityFee) {
        tax = _tax;
        securityFee = _securityFee;
    }

    mapping(uint => AptStruct) apts;
    mapping(uint => BookingStruct[]) bookings;
    mapping(uint => ReviewStruct[]) reviews;
    mapping(uint => bool) aptExists;
    mapping(uint => uint[]) bookedDates;
    mapping(uint => mapping(uint => bool)) isDateBooked;
    mapping(address => mapping(uint => bool)) hasBooked;

    function currentTime() internal view returns (uint256) {
        return (block.timestamp * 1000) + 1000;
    }

    function createApt(
        string memory name,
        string memory desc,
        string memory loc,
        string memory images,
        uint rooms,
        uint price
    ) public {
        require(bytes(name).length > 0, 'Name cannot be empty.');
        require(bytes(desc).length > 0, 'Description cannot be empty.');
        require(bytes(loc).length > 0, 'Location cannot be empty.');
        require(bytes(images).length > 0, 'Images cannot be empty.');
        require(rooms > 0, 'Rooms cannot be zero.');
        require(price > 0 ether, 'Price cannot be zero.');

        _totalApts.increment();

        AptStruct memory apt;
        
        apt.id = _totalApts.current();
        apt.name = name;
        apt.desc = desc;
        apt.loc = loc;
        apt.images = images;
        apt.rooms = rooms;
        apt.price = price;
        apt.owner = msg.sender;
        apt.timestamp = currentTime();

        aptExists[apt.id] = true;
        apts[apt.id] = apt;

    }

    function updateApt(
        uint id,
        string memory name,
        string memory desc,
        string memory loc,
        string memory images,
        uint rooms,
        uint price
    ) public {
        require(aptExists[id], 'Apartment does not exist.');
        require(msg.sender == apts[id].owner, 'Only owner can update.');
        require(bytes(name).length > 0, 'Name cannot be empty.');
        require(bytes(desc).length > 0, 'Description cannot be empty.');
        require(bytes(loc).length > 0, 'Location cannot be empty.');
        require(bytes(images).length > 0, 'Images cannot be empty.');
        require(rooms > 0, 'Rooms cannot be zero.');
        require(price > 0 ether, 'Price cannot be zero.');

        AptStruct memory apt = apts[id];
        
        apt.name = name;
        apt.desc = desc;
        apt.loc = loc;
        apt.images = images;
        apt.rooms = rooms;
        apt.price = price;

        apts[apt.id] = apt;
        
    }

    function deleteApt(
        uint id
    ) public {
        require(aptExists[id], 'Apartment does not exist.');
        require(msg.sender == apts[id].owner, 'Only owner can delete.');

        aptExists[id] = false;
        apts[id].deleted = true;
    }

    function getApt(uint id) public view returns (AptStruct memory) {
        return apts[id];
    }

    function getApts() public view returns (AptStruct[] memory Apts) {
        uint256 size;
        for(uint i=1; i<_totalApts.current();i++){
            if(!apts[i].deleted) size++;
        }

        Apts = new AptStruct[](size);
        uint256 index = 0;
        for(uint i=1; i<_totalApts.current();i++){
            if(!apts[i].deleted) Apts[index++] = apts[i];
        }
    }

    function datesAvailable(uint aptid, uint[] memory dates) internal view returns (bool) {
        bool avail = true;
        // for(uint i=0; i<dates.length;i++){
        //     for(uint j=0; j<bookedDates[aptid].length;j++){
        //         if (dates[i] == bookedDates[aptid][j]){
        //             avail = false;
        //             break;
        //         }
        //     }
        // }

        for(uint i=0; i<dates.length;i++){
            if(isDateBooked[aptid][dates[i]]){
                avail = false;
                break;
            }
        }
        return avail;
    }

    function bookApt(uint aptid, uint[] memory dates) public payable {
        require(aptExists[aptid], 'Apartment does not exist.');
        require(msg.value >= (apts[aptid].price * dates.length * (1+(securityFee/100))), 'Insufficient funds.');
        require(datesAvailable(aptid, dates), 'Dates not avaiable.');

        for(uint i=0; i<dates.length;i++){
            BookingStruct memory booking;
            booking.id = bookings[aptid].length;
            booking.aptid = aptid;
            booking.tenant = msg.sender;
            booking.date = dates[i];
            booking.price = apts[aptid].price;

            bookings[aptid].push(booking);

            isDateBooked[aptid][dates[i]] = true;
            bookedDates[aptid].push(dates[i]);
        }
    }

    function payTo(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}('');
        require(success);
    }

    function checkInApt(uint aptid, uint bookingid) public nonReentrant(){
        BookingStruct memory booking = bookings[aptid][bookingid];
        require(msg.sender == booking.tenant, 'Only booking tenant can check in');
        require(!booking.checked, 'Apartment already checked into.');

        bookings[aptid][bookingid].checked = true;
        hasBooked[msg.sender][booking.date] = true;

        uint _tax = booking.price * tax/100;
        uint _fee = booking.price * securityFee/100;

        payTo(apts[aptid].owner, booking.price - _tax);
        payTo(owner(),tax);
        payTo(booking.tenant, _fee);
    }

    function refundBooking(uint aptid, uint bookingid) public nonReentrant(){
        BookingStruct memory booking = bookings[aptid][bookingid];
        require(!booking.checked, 'Apartment already checked into.');
        require(isDateBooked[aptid][booking.date], 'Date not booked.');

        if(msg.sender != owner()){
            require(msg.sender == booking.tenant, 'Only tenant can get refund.');
            require(booking.date > currentTime(), 'Exceeded cancellation period.');
        }

        bookings[aptid][bookingid].cancelled = true;
        isDateBooked[aptid][booking.date] = false;

        uint lastIndex = bookedDates[aptid].length - 1;
        uint lastBooking = bookedDates[aptid][lastIndex];
        bookedDates[aptid][bookingid] = lastBooking;
        bookedDates[aptid].pop();

        uint _fee = booking.price * securityFee/100;
        uint _collateral = _fee/2;

        payTo(apts[aptid].owner, _collateral);
        payTo(owner(), _collateral);
        payTo(booking.tenant, booking.price);
    }

    function claimFunds(uint aptid, uint bookingid) public nonReentrant{
        require(msg.sender == apts[aptid].owner, 'Unauthorized entity');
        require(!bookings[aptid][bookingid].checked, 'Apartment already checked on this date!');

        uint price = bookings[aptid][bookingid].price;
        uint fee = (price * tax) / 100;

        payTo(apts[aptid].owner, (price - fee));
        payTo(owner(), fee);
        payTo(msg.sender, securityFee);
    }

    function getBookings(uint aptid, uint bookingid) public view returns (BookingStruct memory) {
        return bookings[aptid][bookingid]; 
    }
    
    function getBookings(uint aptid) public view returns (BookingStruct[] memory) {
        return bookings[aptid]; 
    }

    function getUnavailableDates(uint aptid) public view returns (uint[] memory) {
        return bookedDates[aptid]; 
    }

    function addReview(uint aptid, string memory text) internal{
        require(aptExists[aptid], 'Apartment does not exist.');
        require(hasBooked[msg.sender][aptid], 'Must book apartment before reviewing.');
        require(bytes(text).length > 0, 'Review cannot be empty.');

        ReviewStruct memory review;
        review.id = reviews[aptid].length;
        review.aptid = aptid;
        review.text = text;
        review.owner = msg.sender;
        review.timestamp = currentTime();

        reviews[aptid].push(review);
    }

    function getReviews(uint aptid) public view returns (ReviewStruct[] memory){
        return reviews[aptid];
    }

    function tenantBooked(uint aptid) public view returns (bool){
        return hasBooked[msg.sender][aptid];
    }

    function getQualifiedReviwers(uint aptid) public view returns (address[] memory Tenants){
        uint256 size;
        for(uint i=0; i<bookings[aptid].length; i++){
            if(bookings[aptid][i].checked) size++;
        }

        Tenants = new address[](size);

        uint256 index;
        for(uint i=0; i<bookings[aptid].length; i++){
            if(bookings[aptid][i].checked) Tenants[index++] = bookings[aptid][i].tenant;
        }
    }
}