# Phase 4: Mock Integration Testing Guide

## 🎯 Overview

Phase 4 adds **mock integration endpoints** to test the complete user flow without real Razorpay or Meta API credentials.

---

## 🚀 What's Included

### Backend Mock APIs

**File:** [controllers/mockController.js](file:///c:/agency-website/dashboard/server/controllers/mockController.js)

1. **POST /api/mock/recharge**
   - Simulates wallet recharge
   - Adds credits using `walletService.addCredits()`
   - Returns new balance

2. **POST /api/mock/connect-whatsapp**
   - Simulates Meta Embedded Signup
   - Generates mock credentials
   - Inserts into `channels` table

3. **DELETE /api/mock/disconnect-whatsapp**
   - Helper to clean up test channels

**File:** [routes/mockRoutes.js](file:///c:/agency-website/dashboard/server/routes/mockRoutes.js)

- Registers mock endpoints under `/api/mock/*`
- Only enabled when `NODE_ENV !== "production"`

### Frontend Integration

**Updated:** [Wallet.jsx](file:///c:/agency-website/dashboard/src/pages/Wallet.jsx)

- "Recharge Wallet" button now prompts for amount
- Calls `POST /api/mock/recharge`
- Refreshes balance on success
- **TODO comment** for Razorpay integration

**Updated:** [Channels.jsx](file:///c:/agency-website/dashboard/src/pages/Channels.jsx)

- "Connect WhatsApp" button prompts for phone number
- Calls `POST /api/mock/connect-whatsapp`
- Refreshes channel list on success
- **TODO comment** for Meta Embedded Signup

---

## 🧪 Testing Phase 4

### Prerequisites

1. **Start backend server:**

   ```bash
   cd server
   node index-multitenant.js
   ```

   Should see: `🧪 Mock routes enabled (development mode)`

2. **Start frontend:**

   ```bash
   cd dashboard
   npm run dev
   ```

3. **Ensure you have:**
   - Valid `org_id` in your profile
   - User logged in

---

### Test 1: Mock Wallet Recharge

**Steps:**

1. Navigate to `/wallet` in dashboard
2. Click **"Recharge Wallet"** button
3. Enter amount in prompt (e.g., `500`)
4. Click OK

**Expected:**

- Toast: "Processing recharge of ₹500..."
- After 1 second delay (simulated processing)
- Toast: "✅ Recharge successful! New balance: ₹XXX"
- Wallet balance updates automatically
- New transaction appears in history

**Verify in Database:**

```sql
SELECT * FROM transactions
WHERE org_id = 'your-org-uuid'
ORDER BY created_at DESC
LIMIT 1;

-- Should show:
-- type: 'credit'
-- amount: 500.00
-- description: '[MOCK] Wallet recharge via demo payment'
```

---

### Test 2: Mock WhatsApp Connection

**Steps:**

1. Navigate to `/channels`
2. Click **"Connect WhatsApp"** button
3. Enter phone number (e.g., `+919876543210`)
4. Click OK
5. Enter display name (e.g., `Test Business`)
6. Click OK

**Expected:**

- Toast: "Connecting WhatsApp account..."
- After 1.5 second delay (simulated API call)
- Toast: "✅ WhatsApp connected successfully!"
- Warning toast: "⚠️ This is a mock connection..."
- New WhatsApp card appears with "Connected" badge

**Verify in Database:**

```sql
SELECT * FROM channels
WHERE org_id = 'your-org-uuid';

-- Should show:
-- platform: 'whatsapp'
-- status: 'connected'
-- phone_number_id: 'mock_XXXXXXXXXXXXX'
-- waba_id: 'waba_mock_XXXXXX'
-- access_token: 'EAAxxxxxxxxxxxxx'
```

---

### Test 3: End-to-End Message Send Flow

**Complete User Flow:**

1. **Recharge Wallet** (Test 1)
   - Add ₹100 to wallet
   - Verify balance shows ₹100

2. **Connect WhatsApp** (Test 2)
   - Connect mock channel
   - Verify channel shows "Connected"

3. **Send Message** (from AdminDashboard)
   - Go to main dashboard
   - Select a contact
   - Send a test message
   - **Expected outcome:**
     - Wallet deducts ₹0.20 (service fee)
     - Message appears in chat
     - **Meta API call will FAIL** (mock token is invalid)
     - **Service fee will be REFUNDED** automatically

**Why Meta API Fails:**

- Mock access token is not real
- Meta will reject with authentication error
- Backend detects this as "refundable error"
- Automatically refunds the ₹0.20

**Verify Refund:**

```sql
SELECT * FROM transactions
WHERE org_id = 'your-org-uuid'
ORDER BY created_at DESC
LIMIT 2;

-- Should show TWO transactions:
-- 1. type: 'debit', amount: 0.20 (initial deduction)
-- 2. type: 'credit', amount: 0.20 (refund)
```

---

## 🔄 Mock vs Production Comparison

### Wallet Recharge

| Step         | Mock (Phase 4)          | Production                                |
| ------------ | ----------------------- | ----------------------------------------- |
| UI Trigger   | Button click → Prompt   | Button click → Razorpay modal             |
| Payment      | Simulated (instant)     | Real payment gateway                      |
| Backend      | POST /api/mock/recharge | Razorpay webhook to /api/razorpay/webhook |
| Verification | None                    | Signature verification required           |
| Credits      | Added directly          | Added after payment confirmed             |

### WhatsApp Connection

| Step        | Mock (Phase 4)                  | Production                          |
| ----------- | ------------------------------- | ----------------------------------- |
| UI Trigger  | Button click → Prompt           | Button click → Meta modal           |
| OAuth       | Simulated                       | Meta Embedded Signup OAuth flow     |
| Credentials | Random generated                | Real from Meta API                  |
| Backend     | POST /api/mock/connect-whatsapp | Meta callback to /api/meta/callback |
| Token       | Invalid mock string             | Valid permanent access token        |

---

## 📝 TODO Comments Guide

All TODO comments indicate where real integrations should replace mock code:

### In Wallet.jsx

```javascript
// TODO: Replace with Razorpay Checkout SDK open()
// In production:
// 1. Open Razorpay checkout: window.Razorpay({ key: "...", amount: ... })
// 2. On success, backend receives webhook
// 3. Backend verifies signature and adds credits
// 4. Frontend refreshes wallet data
```

**What to do:**

1. Install Razorpay SDK: `npm install razorpay`
2. Add script to `index.html`: `<script src="https://checkout.razorpay.com/v1/checkout.js"></script>`
3. Replace `handlePayment()` function with Razorpay checkout
4. Create backend webhook handler at `/api/razorpay/webhook`

### In Channels.jsx

```javascript
// TODO: Replace with launchWhatsAppSignup() SDK function
// In production:
// 1. Load Meta SDK: fbq('init', 'your-app-id')
// 2. Call: FB.login(launchWhatsAppSignup, {config_id: 'your-config-id'})
// 3. User selects WABA in Meta modal
// 4. Meta redirects to callback with code
// 5. Backend exchanges code for permanent token
// 6. Backend stores in channels table
```

**What to do:**

1. Create Meta App at developers.facebook.com
2. Enable WhatsApp Business Management
3. Create Embedded Signup configuration
4. Add Meta SDK to frontend
5. Replace `handleConnectWhatsApp()` with SDK call
6. Create backend callback at `/api/meta/callback`

### In mockController.js

```javascript
// TODO: This endpoint is for DEMO only.
// Replace with Razorpay Webhook handler in Production.
```

```javascript
// TODO: Replace this with Meta Embedded Signup OAuth Callback.
```

---

## 🛡️ Security Notes

### Disabling Mock Routes in Production

Mock routes are automatically disabled when `NODE_ENV=production`:

```javascript
// In index-multitenant.js
if (process.env.NODE_ENV !== "production") {
  app.use("/api/mock", mockRoutes);
}
```

**Before deploying to production:**

1. Set environment variable:

   ```bash
   export NODE_ENV=production
   ```

2. Verify mock routes are disabled:
   ```bash
   # Should return 404
   curl http://your-domain.com/api/mock/recharge
   ```

### Why Mock Routes Are Dangerous in Production

- Anyone could recharge any wallet for free
- Anyone could create fake WhatsApp connections
- No payment verification
- No authentication on mock endpoints

**ALWAYS disable in production!**

---

## ✅ Phase 4 Complete!

You can now test the **complete user flow** without external dependencies:

1. ✅ User signup/login
2. ✅ Wallet recharge (mock)
3. ✅ WhatsApp connection (mock)
4. ✅ Message sending (with mock credentials)
5. ✅ Balance deduction & refund logic
6. ✅ Transaction history
7. ✅ Channel management

**Next Steps:**

- 🔑 Get Razorpay credentials
- 🔑 Get Meta API credentials
- 🔄 Replace mock endpoints with real integrations
- 🚀 Deploy to production

**Your SaaS platform is functionally complete and ready for real integration!** 🎉
