import { render, screen, waitFor } from '@testing-library/react';
import App from './App';
import { describe, it, expect, vi, beforeEach } from 'vitest';

describe('App', () => {
    beforeEach(() => {
        // Clear mocks before each test
        vi.clearAllMocks();
    });

    it('renders loading state initially', () => {
        // Mock fetch that doesn't resolve immediately
        globalThis.fetch = vi.fn(() => new Promise(() => {}));
        
        render(<App />);
        expect(screen.getByText(/Loading backend status.../i)).toBeInTheDocument();
    });

    it('renders backend data on successful fetch', async () => {
        const mockData = { status: 'ok', message: 'Test Msg', timestamp: 'now' };
        
        globalThis.fetch = vi.fn().mockResolvedValue({
            json: () => Promise.resolve(mockData)
        });

        render(<App />);

        // Wait for the data to be displayed
        await waitFor(() => {
            expect(screen.getByText(/Status:/i)).toBeInTheDocument();
            expect(screen.getByText('ok')).toHaveClass('status-ok');
            expect(screen.getByText(/Test Msg/i)).toBeInTheDocument();
        });
    });

    it('handles fetch errors gracefully (logs to console)', async () => {
        const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        globalThis.fetch = vi.fn().mockRejectedValue(new Error('Network error'));

        render(<App />);

        await waitFor(() => {
            expect(consoleSpy).toHaveBeenCalledWith('Error fetching health check:', expect.any(Error));
        });

        consoleSpy.mockRestore();
    });
});