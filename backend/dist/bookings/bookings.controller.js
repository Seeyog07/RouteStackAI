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
var _a;
Object.defineProperty(exports, "__esModule", { value: true });
exports.BookingsController = void 0;
const common_1 = require("@nestjs/common");
const express_1 = require("express");
const bookings_service_1 = require("./bookings.service");
const create_booking_dto_1 = require("./dto/create-booking.dto");
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
    async proxySearchDestinations(body) {
        const res = await this.service.searchDestinations(body.query);
        return res.body;
    }
    async proxySearchHotels(body) {
        const res = await this.service.searchHotels(body);
        return res.body;
    }
    async proxyGetHotelDetails(body) {
        const res = await this.service.getHotelDetails(body.hotelId);
        return res.body;
    }
    async proxyGetRoomsAndRates(body) {
        const res = await this.service.getRoomsAndRates(body.token, body.hotelId, body.checkIn, body.checkOut, body.rooms);
        return res.body;
    }
    async proxyGetPaymentUrl(body) {
        const res = await this.service.getPaymentUrl(body);
        return res.body;
    }
    async proxyRevalidateHotel(body) {
        const res = await this.service.revalidateHotel(body.token, body.recommendationId, body.hotelId);
        return res.body;
    }
    async proxyGetBookingInfo(body) {
        const res = await this.service.getBookingInfo(body.bookingId);
        return res.body;
    }
    async proxyCancelBooking(body) {
        const res = await this.service.cancelBooking(body.bookingId);
        return res.body;
    }
    async imageProxy(url, res) {
        if (!url) {
            throw new common_1.BadRequestException('url query parameter is required');
        }
        try {
            const decodedUrl = decodeURIComponent(url);
            const fetched = await fetch(decodedUrl);
            if (!fetched.ok) {
                throw new common_1.HttpException('Unable to fetch image', fetched.status);
            }
            const contentType = fetched.headers.get('content-type') || 'application/octet-stream';
            const cacheControl = fetched.headers.get('cache-control') || 'public, max-age=3600';
            res.setHeader('Content-Type', contentType);
            res.setHeader('Cache-Control', cacheControl);
            const buffer = Buffer.from(await fetched.arrayBuffer());
            res.send(buffer);
        }
        catch (error) {
            console.error('image-proxy error:', error);
            throw new common_1.HttpException('Image proxy error', common_1.HttpStatus.BAD_GATEWAY);
        }
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
    (0, common_1.Post)('mcp/hotel/search-destinations'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "proxySearchDestinations", null);
__decorate([
    (0, common_1.Post)('mcp/hotel/search-hotels'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "proxySearchHotels", null);
__decorate([
    (0, common_1.Post)('mcp/hotel/get-hotel-details'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "proxyGetHotelDetails", null);
__decorate([
    (0, common_1.Post)('mcp/hotel/get-rooms-and-rates'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "proxyGetRoomsAndRates", null);
__decorate([
    (0, common_1.Post)('mcp/hotel/get-payment-url'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "proxyGetPaymentUrl", null);
__decorate([
    (0, common_1.Post)('mcp/hotel/revalidate'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "proxyRevalidateHotel", null);
__decorate([
    (0, common_1.Post)('mcp/hotel/get-booking-info'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "proxyGetBookingInfo", null);
__decorate([
    (0, common_1.Post)('mcp/hotel/cancel-booking'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "proxyCancelBooking", null);
__decorate([
    (0, common_1.Get)('image-proxy'),
    __param(0, (0, common_1.Query)('url')),
    __param(1, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, typeof (_a = typeof express_1.Response !== "undefined" && express_1.Response) === "function" ? _a : Object]),
    __metadata("design:returntype", Promise)
], BookingsController.prototype, "imageProxy", null);
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