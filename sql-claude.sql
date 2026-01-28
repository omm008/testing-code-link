-- ============================================================================
-- MULTI-TENANT WHATSAPP BOT MIGRATION TO TECH PROVIDER ARCHITECTURE
-- Supabase (PostgreSQL) Schema for SaaS Multi-tenancy
-- ============================================================================
-- Author: Senior Database Architect
-- Date: 2026-01-28
-- Purpose: Migrate single-tenant to multi-tenant Tech Provider model
-- ============================================================================

-- ============================================================================
-- SECTION 1: EXTENSIONS & ENUMS
-- ============================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create ENUM types for better data integrity
DO $$ BEGIN
    CREATE TYPE platform_type AS ENUM ('whatsapp', 'instagram', 'facebook');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE channel_status_type AS ENUM ('connected', 'disconnected', 'suspended', 'pending');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE transaction_type AS ENUM ('credit', 'debit');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE organization_tier AS ENUM ('free', 'pro', 'enterprise');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('owner', 'admin', 'member', 'viewer');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- SECTION 2: CORE TABLES - ORGANIZATIONS & PROFILES
-- ============================================================================

-- Organizations table (The root tenant entity)
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    service_fee_per_msg DECIMAL(10, 4) NOT NULL DEFAULT 0.20,
    tier organization_tier NOT NULL DEFAULT 'free',
    is_active BOOLEAN NOT NULL DEFAULT true,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_organizations_tier ON organizations(tier);
CREATE INDEX IF NOT EXISTS idx_organizations_active ON organizations(is_active);

-- Profiles table (Links Supabase Auth users to Organizations)
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'member',
    full_name TEXT,
    avatar_url TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for profiles
CREATE INDEX IF NOT EXISTS idx_profiles_org_id ON profiles(org_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);

-- ============================================================================
-- SECTION 3: CREDENTIALS MANAGEMENT (TECH PROVIDER CORE)
-- ============================================================================

-- Channels table (Stores client's WhatsApp/Social credentials)
CREATE TABLE IF NOT EXISTS channels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    platform platform_type NOT NULL,
    waba_id TEXT,
    phone_number_id TEXT UNIQUE NOT NULL,
    phone_number TEXT,
    display_name TEXT,
    access_token TEXT NOT NULL, -- Encrypted in production with Supabase Vault
    webhook_verify_token TEXT,
    status channel_status_type NOT NULL DEFAULT 'pending',
    metadata JSONB DEFAULT '{}',
    connected_at TIMESTAMP WITH TIME ZONE,
    last_sync_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(org_id, phone_number_id)
);

-- Indexes for channels
CREATE INDEX IF NOT EXISTS idx_channels_org_id ON channels(org_id);
CREATE INDEX IF NOT EXISTS idx_channels_phone_number_id ON channels(phone_number_id);
CREATE INDEX IF NOT EXISTS idx_channels_platform ON channels(platform);
CREATE INDEX IF NOT EXISTS idx_channels_status ON channels(status);

-- ============================================================================
-- SECTION 4: WALLET & BILLING SYSTEM
-- ============================================================================

-- Wallets table (One-to-One with Organizations)
CREATE TABLE IF NOT EXISTS wallets (
    org_id UUID PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
    balance DECIMAL(12, 4) NOT NULL DEFAULT 0.00,
    currency TEXT NOT NULL DEFAULT 'INR',
    low_balance_threshold DECIMAL(12, 4) DEFAULT 100.00,
    is_locked BOOLEAN NOT NULL DEFAULT false,
    last_recharged_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT balance_non_negative CHECK (balance >= 0)
);

-- Transactions table (Audit trail for all wallet operations)
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(org_id) ON DELETE CASCADE,
    amount DECIMAL(12, 4) NOT NULL,
    type transaction_type NOT NULL,
    description TEXT NOT NULL,
    reference_id TEXT, -- External payment gateway reference
    metadata JSONB DEFAULT '{}',
    balance_before DECIMAL(12, 4),
    balance_after DECIMAL(12, 4),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for transactions
CREATE INDEX IF NOT EXISTS idx_transactions_org_id ON transactions(org_id);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_reference_id ON transactions(reference_id);

-- ============================================================================
-- SECTION 5: MIGRATION OF EXISTING TABLES (CONTACTS & MESSAGES)
-- ============================================================================

-- Add org_id to contacts table (if exists)
DO $$ 
BEGIN
    -- Add org_id column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'contacts' AND column_name = 'org_id'
    ) THEN
        ALTER TABLE contacts ADD COLUMN org_id UUID;
        
        -- If there's existing data, assign to a default organization
        -- You'll need to manually update this with actual org_id values
        -- For now, we'll make it nullable until migration is complete
        
        -- Add foreign key constraint
        ALTER TABLE contacts ADD CONSTRAINT fk_contacts_org 
            FOREIGN KEY (org_id) REFERENCES organizations(id) ON DELETE CASCADE;
        
        -- Create index
        CREATE INDEX idx_contacts_org_id ON contacts(org_id);
    END IF;
    
    -- Add channel_id for better routing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'contacts' AND column_name = 'channel_id'
    ) THEN
        ALTER TABLE contacts ADD COLUMN channel_id UUID REFERENCES channels(id) ON DELETE SET NULL;
        CREATE INDEX idx_contacts_channel_id ON contacts(channel_id);
    END IF;
END $$;

-- Add org_id to messages table (if exists)
DO $$ 
BEGIN
    -- Add org_id column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'messages' AND column_name = 'org_id'
    ) THEN
        ALTER TABLE messages ADD COLUMN org_id UUID;
        
        -- Add foreign key constraint
        ALTER TABLE messages ADD CONSTRAINT fk_messages_org 
            FOREIGN KEY (org_id) REFERENCES organizations(id) ON DELETE CASCADE;
        
        -- Create index
        CREATE INDEX idx_messages_org_id ON messages(org_id);
    END IF;
    
    -- Add channel_id for better routing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'messages' AND column_name = 'channel_id'
    ) THEN
        ALTER TABLE messages ADD COLUMN channel_id UUID REFERENCES channels(id) ON DELETE SET NULL;
        CREATE INDEX idx_messages_channel_id ON messages(channel_id);
    END IF;
    
    -- Add service_fee_charged column to track per-message billing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'messages' AND column_name = 'service_fee_charged'
    ) THEN
        ALTER TABLE messages ADD COLUMN service_fee_charged DECIMAL(10, 4);
    END IF;
    
    -- Add billing_status to track deduction status
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'messages' AND column_name = 'billing_status'
    ) THEN
        ALTER TABLE messages ADD COLUMN billing_status TEXT DEFAULT 'pending';
        CREATE INDEX idx_messages_billing_status ON messages(billing_status);
    END IF;
END $$;

-- ============================================================================
-- SECTION 6: ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- Enable RLS on existing tables if they exist
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'contacts') THEN
        ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'messages') THEN
        ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
    END IF;
END $$;

-- Organizations Policies
DROP POLICY IF EXISTS "Users can view their own organization" ON organizations;
CREATE POLICY "Users can view their own organization" ON organizations
    FOR SELECT USING (
        id IN (SELECT org_id FROM profiles WHERE id = auth.uid())
    );

DROP POLICY IF EXISTS "Owners can update their organization" ON organizations;
CREATE POLICY "Owners can update their organization" ON organizations
    FOR UPDATE USING (
        id IN (
            SELECT org_id FROM profiles 
            WHERE id = auth.uid() AND role IN ('owner', 'admin')
        )
    );

-- Profiles Policies
DROP POLICY IF EXISTS "Users can view profiles in their org" ON profiles;
CREATE POLICY "Users can view profiles in their org" ON profiles
    FOR SELECT USING (
        org_id IN (SELECT org_id FROM profiles WHERE id = auth.uid())
    );

DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;
CREATE POLICY "Users can view their own profile" ON profiles
    FOR SELECT USING (id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
CREATE POLICY "Users can update their own profile" ON profiles
    FOR UPDATE USING (id = auth.uid());

-- Channels Policies
DROP POLICY IF EXISTS "Users can view channels in their org" ON channels;
CREATE POLICY "Users can view channels in their org" ON channels
    FOR SELECT USING (
        org_id IN (SELECT org_id FROM profiles WHERE id = auth.uid())
    );

DROP POLICY IF EXISTS "Admins can manage channels" ON channels;
CREATE POLICY "Admins can manage channels" ON channels
    FOR ALL USING (
        org_id IN (
            SELECT org_id FROM profiles 
            WHERE id = auth.uid() AND role IN ('owner', 'admin')
        )
    );

-- Wallets Policies
DROP POLICY IF EXISTS "Users can view their org wallet" ON wallets;
CREATE POLICY "Users can view their org wallet" ON wallets
    FOR SELECT USING (
        org_id IN (SELECT org_id FROM profiles WHERE id = auth.uid())
    );

DROP POLICY IF EXISTS "Only owners can update wallet" ON wallets;
CREATE POLICY "Only owners can update wallet" ON wallets
    FOR UPDATE USING (
        org_id IN (
            SELECT org_id FROM profiles 
            WHERE id = auth.uid() AND role = 'owner'
        )
    );

-- Transactions Policies
DROP POLICY IF EXISTS "Users can view their org transactions" ON transactions;
CREATE POLICY "Users can view their org transactions" ON transactions
    FOR SELECT USING (
        org_id IN (SELECT org_id FROM profiles WHERE id = auth.uid())
    );

DROP POLICY IF EXISTS "System can insert transactions" ON transactions;
CREATE POLICY "System can insert transactions" ON transactions
    FOR INSERT WITH CHECK (
        org_id IN (
            SELECT org_id FROM profiles 
            WHERE id = auth.uid() AND role IN ('owner', 'admin')
        )
    );

-- Contacts Policies (if table exists)
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'contacts') THEN
        DROP POLICY IF EXISTS "Users can view contacts in their org" ON contacts;
        CREATE POLICY "Users can view contacts in their org" ON contacts
            FOR SELECT USING (
                org_id IN (SELECT org_id FROM profiles WHERE id = auth.uid())
            );
        
        DROP POLICY IF EXISTS "Users can manage contacts in their org" ON contacts;
        CREATE POLICY "Users can manage contacts in their org" ON contacts
            FOR ALL USING (
                org_id IN (SELECT org_id FROM profiles WHERE id = auth.uid())
            );
    END IF;
END $$;

-- Messages Policies (if table exists)
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'messages') THEN
        DROP POLICY IF EXISTS "Users can view messages in their org" ON messages;
        CREATE POLICY "Users can view messages in their org" ON messages
            FOR SELECT USING (
                org_id IN (SELECT org_id FROM profiles WHERE id = auth.uid())
            );
        
        DROP POLICY IF EXISTS "Users can manage messages in their org" ON messages;
        CREATE POLICY "Users can manage messages in their org" ON messages
            FOR ALL USING (
                org_id IN (SELECT org_id FROM profiles WHERE id = auth.uid())
            );
    END IF;
END $$;

-- ============================================================================
-- SECTION 7: TRIGGERS & AUTOMATION
-- ============================================================================

-- Function: Auto-create wallet when organization is created
CREATE OR REPLACE FUNCTION create_wallet_for_organization()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO wallets (org_id, balance, currency)
    VALUES (NEW.id, 0.00, 'INR');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_create_wallet ON organizations;
CREATE TRIGGER trigger_create_wallet
    AFTER INSERT ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION create_wallet_for_organization();

-- Function: Auto-create profile when user signs up
CREATE OR REPLACE FUNCTION create_profile_for_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert into profiles table
    -- Note: org_id must be provided during user creation via metadata
    -- or assigned through a separate onboarding flow
    INSERT INTO profiles (id, org_id, role, full_name)
    VALUES (
        NEW.id,
        -- Try to get org_id from user metadata, otherwise NULL
        COALESCE((NEW.raw_user_meta_data->>'org_id')::UUID, NULL),
        COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'member'),
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email)
    )
    ON CONFLICT (id) DO NOTHING;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_create_profile ON auth.users;
CREATE TRIGGER trigger_create_profile
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION create_profile_for_user();

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to relevant tables
DROP TRIGGER IF EXISTS set_updated_at ON organizations;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at ON profiles;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at ON channels;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON channels
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at ON wallets;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON wallets
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function: Record wallet transaction with balance tracking
CREATE OR REPLACE FUNCTION record_wallet_transaction()
RETURNS TRIGGER AS $$
DECLARE
    current_balance DECIMAL(12, 4);
BEGIN
    -- Get current balance
    SELECT balance INTO current_balance FROM wallets WHERE org_id = NEW.org_id;
    
    -- Set balance_before
    NEW.balance_before := current_balance;
    
    -- Calculate new balance
    IF NEW.type = 'credit' THEN
        NEW.balance_after := current_balance + NEW.amount;
    ELSE
        NEW.balance_after := current_balance - NEW.amount;
    END IF;
    
    -- Update wallet balance
    UPDATE wallets 
    SET 
        balance = NEW.balance_after,
        updated_at = NOW(),
        last_recharged_at = CASE WHEN NEW.type = 'credit' THEN NOW() ELSE last_recharged_at END
    WHERE org_id = NEW.org_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_record_transaction ON transactions;
CREATE TRIGGER trigger_record_transaction
    BEFORE INSERT ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION record_wallet_transaction();

-- ============================================================================
-- SECTION 8: HELPER FUNCTIONS
-- ============================================================================

-- Function: Deduct service fee from wallet
CREATE OR REPLACE FUNCTION deduct_service_fee(
    p_org_id UUID,
    p_message_id UUID,
    p_service_fee DECIMAL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_current_balance DECIMAL(12, 4);
BEGIN
    -- Get current wallet balance
    SELECT balance INTO v_current_balance FROM wallets WHERE org_id = p_org_id;
    
    -- Check if sufficient balance
    IF v_current_balance < p_service_fee THEN
        RETURN FALSE;
    END IF;
    
    -- Create debit transaction
    INSERT INTO transactions (org_id, wallet_id, amount, type, description, metadata)
    VALUES (
        p_org_id,
        p_org_id,
        p_service_fee,
        'debit',
        'Service fee for message',
        jsonb_build_object('message_id', p_message_id)
    );
    
    -- Update message billing status
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'messages') THEN
        EXECUTE format('UPDATE messages SET billing_status = ''charged'', service_fee_charged = %s WHERE id = %L', p_service_fee, p_message_id);
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get organization's current balance
CREATE OR REPLACE FUNCTION get_org_balance(p_org_id UUID)
RETURNS DECIMAL AS $$
DECLARE
    v_balance DECIMAL(12, 4);
BEGIN
    SELECT balance INTO v_balance FROM wallets WHERE org_id = p_org_id;
    RETURN COALESCE(v_balance, 0.00);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- SECTION 9: VIEWS FOR REPORTING
-- ============================================================================

-- View: Organization wallet summary
CREATE OR REPLACE VIEW org_wallet_summary AS
SELECT 
    o.id as org_id,
    o.name as org_name,
    o.tier,
    w.balance,
    w.currency,
    w.low_balance_threshold,
    w.is_locked,
    (SELECT COUNT(*) FROM channels WHERE org_id = o.id AND status = 'connected') as active_channels,
    (SELECT SUM(amount) FROM transactions WHERE org_id = o.id AND type = 'credit') as total_credits,
    (SELECT SUM(amount) FROM transactions WHERE org_id = o.id AND type = 'debit') as total_debits,
    w.last_recharged_at,
    o.created_at
FROM organizations o
JOIN wallets w ON o.id = w.org_id;

-- View: Recent transactions
CREATE OR REPLACE VIEW recent_transactions AS
SELECT 
    t.id,
    o.name as org_name,
    t.amount,
    t.type,
    t.description,
    t.balance_before,
    t.balance_after,
    t.created_at
FROM transactions t
JOIN organizations o ON t.org_id = o.id
ORDER BY t.created_at DESC;

-- ============================================================================
-- SECTION 10: SEED DATA (OPTIONAL - COMMENT OUT IF NOT NEEDED)
-- ============================================================================

-- Insert a default organization for migration purposes
-- UNCOMMENT AND MODIFY AS NEEDED
/*
INSERT INTO organizations (name, service_fee_per_msg, tier)
VALUES ('Default Organization', 0.20, 'free')
ON CONFLICT DO NOTHING;
*/

-- ============================================================================
-- SECTION 11: GRANTS & PERMISSIONS
-- ============================================================================

-- Grant necessary permissions to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- Post-migration notes:
-- 1. Update existing contacts and messages with correct org_id values
-- 2. Migrate existing credentials to the channels table
-- 3. Set up Supabase Vault for encrypting access_tokens
-- 4. Configure webhook routing based on phone_number_id
-- 5. Set up cron jobs for:
--    - Low balance notifications
--    - Wallet expiry checks
--    - Channel health monitoring
-- 6. Update application code to handle multi-tenancy
-- 7. Test RLS policies thoroughly before production deployment

SELECT 'Multi-tenant migration completed successfully!' as status;