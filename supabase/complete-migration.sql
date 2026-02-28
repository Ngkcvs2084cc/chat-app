-- ==========================================
-- 完整数据库初始化 - 保留所有原功能
-- ==========================================

-- 启用扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==========================================
-- 表结构
-- ==========================================

-- 1. 用户表
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  gender TEXT NOT NULL,
  avatar_url TEXT NOT NULL,
  location TEXT NOT NULL,
  coins INTEGER DEFAULT 6,
  is_temp BOOLEAN DEFAULT false,
  is_banned BOOLEAN DEFAULT false,
  sent_message_counts JSONB DEFAULT '{}',
  recharge_history JSONB DEFAULT '[]',
  login_history JSONB DEFAULT '[]',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. 在线用户表
CREATE TABLE IF NOT EXISTS online_users (
  id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  username TEXT,
  gender TEXT,
  avatar_url TEXT,
  location TEXT,
  coins INTEGER,
  is_temp BOOLEAN,
  is_online BOOLEAN DEFAULT true,
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. 消息表
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id TEXT NOT NULL,
  sender_id UUID NOT NULL,
  receiver_id UUID NOT NULL,
  text TEXT NOT NULL CHECK (length(text) <= 500),
  read BOOLEAN DEFAULT false,
  timestamp BIGINT DEFAULT extract(epoch from now())::bigint * 1000,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. 输入状态表
CREATE TABLE IF NOT EXISTS typing_status (
  chat_id TEXT PRIMARY KEY,
  user_id UUID NOT NULL,
  is_typing BOOLEAN DEFAULT false,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. 管理员表
CREATE TABLE IF NOT EXISTS admins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. 充值订单表
CREATE TABLE IF NOT EXISTS recharge_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id TEXT UNIQUE NOT NULL,
  user_id UUID REFERENCES users(id),
  coins INTEGER NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_online_users_online ON online_users(is_online, last_seen DESC);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- ==========================================
-- RLS策略
-- ==========================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE online_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE typing_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE admins ENABLE ROW LEVEL SECURITY;

-- 允许所有操作（简化版，生产环境需要更严格）
DROP POLICY IF EXISTS "允许所有" ON users;
CREATE POLICY "允许所有" ON users FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "允许所有" ON online_users;
CREATE POLICY "允许所有" ON online_users FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "允许所有" ON messages;
CREATE POLICY "允许所有" ON messages FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "允许所有" ON typing_status;
CREATE POLICY "允许所有" ON typing_status FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "管理员可见" ON admins;
CREATE POLICY "管理员可见" ON admins FOR ALL USING (true) WITH CHECK (true);

-- ==========================================
-- 数据库函数
-- ==========================================

-- 1. 用户登录
CREATE OR REPLACE FUNCTION login_user(
  p_username TEXT,
  p_password TEXT,
  p_location TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user RECORD;
BEGIN
  SELECT * INTO v_user
  FROM users
  WHERE username = p_username AND password = p_password;

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'error', '用户名或密码错误'
    );
  END IF;

  IF v_user.is_banned THEN
    RETURN json_build_object(
      'success', false,
      'error', '账号已被封禁'
    );
  END IF;

  -- 更新登录历史
  UPDATE users
  SET login_history = COALESCE(login_history, '[]'::jsonb) || 
      jsonb_build_object(
        'timestamp', extract(epoch from now())::bigint * 1000,
        'location', p_location
      )
  WHERE id = v_user.id;

  -- 更新在线状态
  INSERT INTO online_users (
    id, username, gender, avatar_url, location, coins, is_temp, is_online, last_seen
  ) VALUES (
    v_user.id, v_user.username, v_user.gender, v_user.avatar_url, 
    v_user.location, v_user.coins, v_user.is_temp, true, NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    is_online = true,
    last_seen = NOW();

  RETURN json_build_object(
    'success', true,
    'user', row_to_json(v_user)
  );
END;
$$;

-- 2. 用户注册
CREATE OR REPLACE FUNCTION register_user(
  p_username TEXT,
  p_password TEXT,
  p_temp_id TEXT DEFAULT NULL,
  p_gender TEXT DEFAULT 'male',
  p_avatar_url TEXT DEFAULT NULL,
  p_location TEXT DEFAULT '未知',
  p_sent_counts JSONB DEFAULT '{}'
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  -- 检查用户名
  IF EXISTS (SELECT 1 FROM users WHERE username = p_username) THEN
    RETURN json_build_object(
      'success', false,
      'error', '用户名已存在'
    );
  END IF;

  -- 创建用户
  INSERT INTO users (
    username, password, gender, avatar_url, location, 
    coins, is_temp, sent_message_counts
  ) VALUES (
    p_username, p_password, p_gender, 
    COALESCE(p_avatar_url, 'https://api.dicebear.com/7.x/avataaars/svg?seed=' || p_username),
    p_location, 6, false, p_sent_counts
  )
  RETURNING id INTO v_user_id;

  -- 更新在线状态
  INSERT INTO online_users (
    id, username, gender, avatar_url, location, coins, is_temp, is_online
  ) VALUES (
    v_user_id, p_username, p_gender, 
    COALESCE(p_avatar_url, 'https://api.dicebear.com/7.x/avataaars/svg?seed=' || p_username),
    p_location, 6, false, true
  );

  RETURN json_build_object(
    'success', true,
    'userId', v_user_id
  );
END;
$$;

-- 3. 发送消息（带限制）
CREATE OR REPLACE FUNCTION send_message_with_limits(
  p_sender_id UUID,
  p_receiver_id UUID,
  p_text TEXT,
  p_is_temp BOOLEAN DEFAULT false
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sender RECORD;
  v_chat_id TEXT;
  v_message_id UUID;
  v_sent_count INTEGER;
BEGIN
  -- 获取发送者信息
  SELECT * INTO v_sender FROM users WHERE id = p_sender_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', '发送者不存在');
  END IF;

  -- 生成chat_id
  v_chat_id := CASE 
    WHEN p_sender_id::text < p_receiver_id::text 
    THEN p_sender_id::text || '_' || p_receiver_id::text
    ELSE p_receiver_id::text || '_' || p_sender_id::text
  END;

  -- 获取已发送消息数
  v_sent_count := COALESCE(
    (v_sender.sent_message_counts->>p_receiver_id::text)::integer, 
    0
  );

  -- 检查限制
  IF v_sent_count >= 5 THEN
    IF v_sender.is_temp THEN
      RETURN json_build_object(
        'success', false,
        'error', 'TEMP_USER_LIMIT',
        'message', '临时用户只能发送5条免费消息'
      );
    END IF;

    IF v_sender.coins < 2 THEN
      RETURN json_build_object(
        'success', false,
        'error', 'INSUFFICIENT_COINS',
        'message', '金币不足'
      );
    END IF;

    -- 扣除金币
    UPDATE users SET coins = coins - 2 WHERE id = p_sender_id;
  END IF;

  -- 插入消息
  INSERT INTO messages (chat_id, sender_id, receiver_id, text)
  VALUES (v_chat_id, p_sender_id, p_receiver_id, p_text)
  RETURNING id INTO v_message_id;

  -- 更新消息计数
  UPDATE users
  SET sent_message_counts = jsonb_set(
    COALESCE(sent_message_counts, '{}'::jsonb),
    ARRAY[p_receiver_id::text],
    to_jsonb(v_sent_count + 1)
  )
  WHERE id = p_sender_id;

  -- 获取最新金币数
  SELECT coins INTO v_sender FROM users WHERE id = p_sender_id;

  RETURN json_build_object(
    'success', true,
    'messageId', v_message_id,
    'remainingCoins', v_sender.coins
  );
END;
$$;

-- 4. 更新心跳
CREATE OR REPLACE FUNCTION update_heartbeat(
  p_user_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE online_users
  SET last_seen = NOW(), is_online = true
  WHERE id = p_user_id;
  RETURN true;
END;
$$;

-- 5. 充值金币
CREATE OR REPLACE FUNCTION recharge_coins(
  p_user_id UUID,
  p_order_id TEXT,
  p_coins INTEGER,
  p_amount DECIMAL
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_new_balance INTEGER;
BEGIN
  -- 检查订单是否已处理
  IF EXISTS (SELECT 1 FROM recharge_orders WHERE order_id = p_order_id AND status = 'success') THEN
    RETURN json_build_object('success', false, 'error', '订单已处理');
  END IF;

  -- 增加金币
  UPDATE users 
  SET coins = coins + p_coins,
      recharge_history = COALESCE(recharge_history, '[]'::jsonb) ||
        jsonb_build_object(
          'coins', p_coins,
          'amount', p_amount,
          'timestamp', extract(epoch from now())::bigint * 1000,
          'orderId', p_order_id
        )
  WHERE id = p_user_id
  RETURNING coins INTO v_new_balance;

  -- 记录订单
  INSERT INTO recharge_orders (order_id, user_id, coins, amount, status)
  VALUES (p_order_id, p_user_id, p_coins, p_amount, 'success');

  RETURN json_build_object('success', true, 'newBalance', v_new_balance);
END;
$$;

-- 6. 管理员登录
CREATE OR REPLACE FUNCTION admin_login(
  p_username TEXT,
  p_password TEXT
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT * INTO v_admin
  FROM admins
  WHERE username = p_username AND password = p_password;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', '用户名或密码错误');
  END IF;

  RETURN json_build_object('success', true, 'admin', row_to_json(v_admin));
END;
$$;

-- 7. 封禁用户
CREATE OR REPLACE FUNCTION ban_user(
  p_user_id UUID,
  p_banned BOOLEAN
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE users SET is_banned = p_banned WHERE id = p_user_id;
  
  IF p_banned THEN
    UPDATE online_users SET is_online = false WHERE id = p_user_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

-- 8. 更新用户金币（管理员）
CREATE OR REPLACE FUNCTION admin_update_coins(
  p_user_id UUID,
  p_coins INTEGER
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE users SET coins = p_coins WHERE id = p_user_id;
  UPDATE online_users SET coins = p_coins WHERE id = p_user_id;
  RETURN json_build_object('success', true);
END;
$$;

-- 9. 获取统计数据
CREATE OR REPLACE FUNCTION get_stats()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_users INTEGER;
  v_online_users INTEGER;
  v_total_messages INTEGER;
  v_total_coins INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_total_users FROM users;
  SELECT COUNT(*) INTO v_online_users FROM online_users WHERE is_online = true;
  SELECT COUNT(*) INTO v_total_messages FROM messages;
  SELECT COALESCE(SUM(coins), 0) INTO v_total_coins FROM users;

  RETURN json_build_object(
    'totalUsers', v_total_users,
    'onlineUsers', v_online_users,
    'totalMessages', v_total_messages,
    'totalCoins', v_total_coins
  );
END;
$$;

-- ==========================================
-- 启用实时订阅
-- ==========================================

ALTER PUBLICATION supabase_realtime ADD TABLE online_users;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE typing_status;

-- ==========================================
-- 插入测试数据
-- ==========================================

-- 插入管理员账号
INSERT INTO admins (username, password)
VALUES ('admin', 'admin123')
ON CONFLICT (username) DO NOTHING;

-- 插入测试用户
INSERT INTO users (username, password, gender, avatar_url, location, is_temp)
VALUES 
  ('小明', 'test123', 'male', 'https://api.dicebear.com/7.x/avataaars/svg?seed=ming', '北京', false),
  ('小红', 'test123', 'female', 'https://api.dicebear.com/7.x/avataaars/svg?seed=hong', '上海', false)
ON CONFLICT (username) DO NOTHING;

-- 插入在线用户
INSERT INTO online_users (id, username, gender, avatar_url, location, coins, is_temp, is_online)
SELECT id, username, gender, avatar_url, location, coins, is_temp, true
FROM users WHERE username IN ('小明', '小红')
ON CONFLICT (id) DO UPDATE SET is_online = true;

-- ==========================================
-- 完成提示
-- ==========================================

DO $$
BEGIN
  RAISE NOTICE '==========================================';
  RAISE NOTICE '✅ 数据库初始化完成！';
  RAISE NOTICE '==========================================';
  RAISE NOTICE '✅ 已创建6张表：';
  RAISE NOTICE '   - users（用户）';
  RAISE NOTICE '   - online_users（在线用户）';
  RAISE NOTICE '   - messages（消息）';
  RAISE NOTICE '   - typing_status（输入状态）';
  RAISE NOTICE '   - admins（管理员）';
  RAISE NOTICE '   - recharge_orders（充值订单）';
  RAISE NOTICE '';
  RAISE NOTICE '✅ 已创建9个数据库函数';
  RAISE NOTICE '✅ 已配置RLS策略';
  RAISE NOTICE '✅ 已启用实时订阅';
  RAISE NOTICE '✅ 已插入测试数据';
  RAISE NOTICE '';
  RAISE NOTICE '管理员账号：admin / admin123';
  RAISE NOTICE '测试用户：小明 / test123';
  RAISE NOTICE '==========================================';
END $$;
