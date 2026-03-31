const request = require('supertest');
const app = require('../src/app');

describe('End-to-End API Flow', () => {
    
    // Simulate a client checking system status before proceeding
    test('System Health Check Flow', async () => {
        // Step 1: Check root endpoint
        const rootRes = await request(app).get('/');
        expect(rootRes.statusCode).toBe(200);
        expect(rootRes.text).toContain('ShopSmart Backend Service');

        // Step 2: Verify API health
        const healthRes = await request(app).get('/api/health');
        expect(healthRes.statusCode).toBe(200);
        expect(healthRes.body.status).toBe('ok');
        expect(healthRes.body.timestamp).toBeDefined();

        // Step 3: Verify handling of invalid endpoints
        const invalidRes = await request(app).get('/api/invalid-endpoint-check');
        expect(invalidRes.statusCode).toBe(404);
    });
});