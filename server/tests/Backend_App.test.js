const request = require('supertest');
const app = require('../src/app');

describe('Server API Integration Tests', () => {
    
    describe('Security & Configuration', () => {
        it('should have CORS headers enabled', async () => {
            const res = await request(app).get('/api/health');
            expect(res.headers['access-control-allow-origin']).toBeDefined();
        });
    });

    describe('GET /api/health', () => {
        it('should return 200 and status ok', async () => {
            const res = await request(app).get('/api/health');
            expect(res.statusCode).toEqual(200);
            expect(res.headers['content-type']).toMatch(/json/);
            expect(res.body).toHaveProperty('status', 'ok');
            expect(res.body).toHaveProperty('message');
            expect(res.body).toHaveProperty('timestamp');
        });
    });

    describe('GET /', () => {
        it('should return welcome message', async () => {
            const res = await request(app).get('/');
            expect(res.statusCode).toEqual(200);
            expect(res.headers['content-type']).toMatch(/text\/html|text\/plain/);
            expect(res.text).toContain('ShopSmart Backend Service');
        });
    });

    describe('GET /unknown-route', () => {
        it('should return 404', async () => {
            const res = await request(app).get('/api/unknown');
            expect(res.statusCode).toEqual(404);
        });
    });
});