"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.BookingsController = void 0;
const common_1 = require("@nestjs/common");
const bookings_service_1 = require("./bookings.service");
const create_booking_dto_1 = require("./dto/create-booking.dto");
const search_hotels_dto_1 = require("./dto/search-hotels.dto");
let BookingsController = class BookingsController {
    constructor(service) {
        this.service = service;
    }
    async getFlights(from, to) {
        if (!from || !to) {
            throw new common_1.BadRequestException('Please provide "from" and "to" query parameters');
        }
        return await this.service.findFlights(from, to);
    }
    async getHotels(city, checkIn, checkOut) {
        if (!city || !checkIn || !checkOut) {
            throw new common_1.BadRequestException('Please provide city, checkIn, and checkOut query parameters');
        }
        return await this.service.findHotels(city, checkIn, checkOut);
    }
    async proxySearchHotels(body) {
        const res = await this.service.searchHotels(body);
        return res.body;
    }
    createBooking(dto) {
        return this.service.createBooking(dto);
    }
    listBookings() {
        return this.service.listBookings();
    }
};
exports.BookingsController = BookingsController;
__decorate([
    (0, common_1.Get)('flights'),
    __param(0, (0, common_1.Query)('from')),
    __param(1, (0, common_1.Query)('to')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "getFlights", null);
__decorate([
    (0, common_1.Get)('hotels'),
    __param(0, (0, common_1.Query)('city')),
    __param(1, (0, common_1.Query)('checkIn')),
    __param(2, (0, common_1.Query)('checkOut')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "getHotels", null);
__decorate([
    (0, common_1.Post)('mcp/hotel/search-hotels'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [search_hotels_dto_1.SearchHotelsDto]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "proxySearchHotels", null);
__decorate([
    (0, common_1.Post)('book'),
    (0, common_1.HttpCode)(common_1.HttpStatus.CREATED),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_booking_dto_1.CreateBookingDto]),
    __metadata("design:returntype", void 0)
], BookingsController.prototype, "createBooking", null);
__decorate([
    (0, common_1.Get)('bookings'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], BookingsController.prototype, "listBookings", null);
exports.BookingsController = BookingsController = __decorate([
    (0, common_1.Controller)(),
    __metadata("design:paramtypes", [bookings_service_1.BookingsService])
], BookingsController);
//# sourceMappingURL=bookings.controller.js.map