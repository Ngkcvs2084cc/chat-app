-- ==========================================
-- Supabase 匿名聊天系统 - 数据库初始化脚本
-- ==========================================
-- 在 Supabase SQL Editor 中执行此脚本
-- ==========================================

-- 1. 创建用户表
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  gender TEXT NOT NULL CHECK (gender IN ('male', 'female')),
  avatar_url TEXT NOT NULL,
  location TEXT NOT NULL,
  coins INTEGER DEFAULT 6 CHECK (coins >= 0),
  is_temp BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. 创建在线用户表
CREATE TABLE IF NOT EXISTS online_users (
  id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  is_online BOOLEAN DEFAULT true,
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. 创建消息表
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id TEXT NOT NULL,
  sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  text TEXT NOT NULL CHECK (LENGTH(text) > 0 AND LENGTH(text) <= 500),
  read BOOLEAN DEFAULT false,
  read_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- 索引优化
  CONSTRAINT different_users CHECK (sender_id != receiver_id)
);

-- 4. 创建消息计数表
CREATE TABLE IF NOT EXISTS message_counts (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  count INTEGER DEFAULT 0 CHECK (count >= 0),
  PRIMARY KEY (user_id, target_user_id)
);

-- 5. 创建订单表
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id TEXT UNIQUE NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  coins INTEGER NOT NULL CHECK (coins > 0),
  amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'expired')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '30 minutes')
);

-- 6. 创建充值历史表
CREATE TABLE IF NOT EXISTS recharge_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  order_id TEXT NOT NULL,
  coins INTEGER NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7. 创建输入状态表（实时显示"正在输入"）
CREATE TABLE IF NOT EXISTS typing_status (
  chat_id TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  is_typing BOOLEAN DEFAULT false,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (chat_id, user_id)
);

-- ==========================================
-- 创建索引优化查询性能
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_online_users_online ON online_users(is_online, last_seen);
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status, expires_at);

-- ==========================================
-- 创建数据库函数
-- ==========================================

-- 扣除金币函数（原子操作）
CREATE OR REPLACE FUNCTION deduct_coins(
  p_user_id UUID, 
  p_amount INTEGER
)
RETURNS BOOLEAN AS $$
DECLARE
  v_current_coins INTEGER;
BEGIN
  -- 获取当前金币数并锁定行
  SELECT coins INTO v_current_coins
  FROM users
  WHERE id = p_user_id
  FOR UPDATE;
  
  -- 检查金币是否足够
  IF v_current_coins IS NULL THEN
    RAISE EXCEPTION '用户不存在';
  END IF;
  
  IF v_current_coins < p_amount THEN
    RETURN false;
  END IF;
  
  -- 扣除金币
  UPDATE users 
  SET coins = coins - p_amount,
      updated_at = NOW()
  WHERE id = p_user_id;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 增加金币函数（用于充值）
CREATE OR REPLACE FUNCTION add_coins(
  p_user_id UUID, 
  p_amount INTEGER
)
RETURNS VOID AS $$
BEGIN
  UPDATE users 
  SET coins = coins + p_amount,
      updated_at = NOW()
  WHERE id = p_user_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION '用户不存在';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 增加消息计数函数
CREATE OR REPLACE FUNCTION increment_message_count(
  p_user_id UUID, 
  p_target_id UUID
)
RETURNS INTEGER AS $$
DECLARE
  v_new_count INTEGER;
BEGIN
  INSERT INTO message_counts (user_id, target_user_id, count)
  VALUES (p_user_id, p_target_id, 1)
  ON CONFLICT (user_id, target_user_id)
  DO UPDATE SET count = message_counts.count + 1
  RETURNING count INTO v_new_count;
  
  RETURN v_new_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 获取消息计数函数
CREATE OR REPLACE FUNCTION get_message_count(
  p_user_id UUID, 
  p_target_id UUID
)
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT count INTO v_count
  FROM message_counts
  WHERE user_id = p_user_id AND target_user_id = p_target_id;
  
  RETURN COALESCE(v_count, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 清理过期订单函数（定时任务会调用）
CREATE OR REPLACE FUNCTION cleanup_expired_orders()
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE orders
  SET status = 'expired'
  WHERE status = 'pending' 
    AND expires_at < NOW()
  RETURNING COUNT(*) INTO v_count;
  
  RETURN COALESCE(v_count, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 启用 Row Level Security (RLS)
-- ==========================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE online_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE recharge_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE typing_status ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 创建 RLS 策略
-- ==========================================

-- 用户表策略
DROP POLICY IF EXISTS "用户只能查看自己的完整数据" ON users;
CREATE POLICY "用户只能查看自己的完整数据" 
  ON users FOR SELECT 
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "用户可以创建账号" ON users;
CREATE POLICY "用户可以创建账号" 
  ON users FOR INSERT 
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "用户只能更新自己的非敏感字段" ON users;
CREATE POLICY "用户只能更新自己的非敏感字段" 
  ON users FOR UPDATE 
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id AND
    -- 禁止修改金币和密码（只能通过函数修改）
    coins = (SELECT coins FROM users WHERE id = auth.uid()) AND
    password_hash = (SELECT password_hash FROM users WHERE id = auth.uid())
  );

-- 在线用户表策略（所有已认证用户可以查看）
DROP POLICY IF EXISTS "所有用户可以查看在线状态" ON online_users;
CREATE POLICY "所有用户可以查看在线状态" 
  ON online_users FOR SELECT 
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "用户只能更新自己的在线状态" ON online_users;
CREATE POLICY "用户只能更新自己的在线状态" 
  ON online_users FOR ALL 
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- 消息表策略
DROP POLICY IF EXISTS "用户只能查看自己的消息" ON messages;
CREATE POLICY "用户只能查看自己的消息" 
  ON messages FOR SELECT 
  USING (
    auth.uid() = sender_id OR 
    auth.uid() = receiver_id
  );

DROP POLICY IF EXISTS "禁止前端直接创建消息" ON messages;
CREATE POLICY "禁止前端直接创建消息" 
  ON messages FOR INSERT 
  WITH CHECK (false);

DROP POLICY IF EXISTS "用户只能标记自己收到的消息为已读" ON messages;
CREATE POLICY "用户只能标记自己收到的消息为已读" 
  ON messages FOR UPDATE 
  USING (auth.uid() = receiver_id)
  WITH CHECK (
    auth.uid() = receiver_id AND
    -- 只能修改read和read_at字段
    sender_id = (SELECT sender_id FROM messages WHERE id = messages.id) AND
    text = (SELECT text FROM messages WHERE id = messages.id)
  );

-- 消息计数表策略
DROP POLICY IF EXISTS "用户只能查看自己的计数" ON message_counts;
CREATE POLICY "用户只能查看自己的计数" 
  ON message_counts FOR SELECT 
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "禁止前端修改计数" ON message_counts;
CREATE POLICY "禁止前端修改计数" 
  ON message_counts FOR ALL 
  USING (false)
  WITH CHECK (false);

-- 订单表策略
DROP POLICY IF EXISTS "用户只能查看自己的订单" ON orders;
CREATE POLICY "用户只能查看自己的订单" 
  ON orders FOR SELECT 
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "禁止前端操作订单" ON orders;
CREATE POLICY "禁止前端操作订单" 
  ON orders FOR ALL 
  USING (false)
  WITH CHECK (false);

-- 充值历史表策略
DROP POLICY IF EXISTS "用户只能查看自己的充值记录" ON recharge_history;
CREATE POLICY "用户只能查看自己的充值记录" 
  ON recharge_history FOR SELECT 
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "禁止前端操作充值记录" ON recharge_history;
CREATE POLICY "禁止前端操作充值记录" 
  ON recharge_history FOR ALL 
  USING (false)
  WITH CHECK (false);

-- 输入状态表策略
DROP POLICY IF EXISTS "用户可以查看聊天中的输入状态" ON typing_status;
CREATE POLICY "用户可以查看聊天中的输入状态" 
  ON typing_status FOR SELECT 
  USING (
    auth.uid() IS NOT NULL AND
    chat_id LIKE '%' || auth.uid()::text || '%'
  );

DROP POLICY IF EXISTS "用户可以更新自己的输入状态" ON typing_status;
CREATE POLICY "用户可以更新自己的输入状态" 
  ON typing_status FOR ALL 
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ==========================================
-- 创建实时订阅
-- ==========================================

-- 启用实时功能
ALTER PUBLICATION supabase_realtime ADD TABLE online_users;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE typing_status;

-- ==========================================
-- 初始化完成
-- ==========================================

-- 插入测试数据（可选，生产环境删除）
-- INSERT INTO users (id, username, password_hash, gender, avatar_url, location, is_temp)
-- VALUES 
--   (gen_random_uuid(), 'test_user', '$2a$10$...', 'male', 'https://api.dicebear.com/7.x/avataaars/svg?seed=test', '北京', false);

COMMENT ON TABLE users IS '用户表 - 存储用户基本信息';
COMMENT ON TABLE messages IS '消息表 - 存储聊天消息';
COMMENT ON TABLE online_users IS '在线用户表 - 存储用户在线状态';
COMMENT ON TABLE orders IS '订单表 - 存储充值订单';

-- 显示成功消息
DO $$
BEGIN
  RAISE NOTICE '✅ 数据库初始化成功！';
  RAISE NOTICE '✅ 所有表已创建';
  RAISE NOTICE '✅ RLS策略已配置';
  RAISE NOTICE '✅ 索引已优化';
  RAISE NOTICE '✅ 数据库函数已创建';
  RAISE NOTICE '';
  RAISE NOTICE '🎉 下一步：部署 Edge Functions';
END $$;
