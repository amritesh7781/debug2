import { test, expect } from '@playwright/test';

test('has title and connects to api', async ({ page }) => {
  await page.goto('/');

  await expect(page).toHaveTitle(/ShopSmart/i);

  const heading = page.locator('h1');
  await expect(heading).toHaveText('ShopSmart');
  
  const backendStatus = page.locator('h2', { hasText: 'Backend Status' });
  await expect(backendStatus).toBeVisible();
});
