// ==========================================
// Supabase 适配层 - 完整功能库
// 用于替代Firebase的所有功能
// ==========================================

// 初始化Supabase客户端（在HTML中调用）
const initSupabase = (url, anonKey) => {
  if (typeof window.supabase === 'undefined') {
    console.error('❌ Supabase SDK未加载，请确保引入了SDK');
    return null;
  }
  return window.supabase.createClient(url, anonKey);
};

// ==========================================
// 核心适配器类
// ==========================================

class SupabaseAdapter {
  constructor(supabaseClient) {
    this.supabase = supabaseClient;
    this.subscriptions = new Map();
  }

  // ==========================================
  // 1. 用户相关
  // ==========================================

  // 登录用户
  async loginUser(username, password, location) {
    try {
      const { data, error } = await this.supabase.rpc('login_user', {
        p_username: username,
        p_password: password,
        p_location: location
      });

      if (error) throw error;
      
      if (!data.success) {
        return { success: false, error: data.error };
      }

      return { success: true, user: data.user };
    } catch (error) {
      console.error('登录失败:', error);
      return { success: false, error: error.message };
    }
  }

  // 注册用户
  async registerUser(username, password, tempId, gender, avatarUrl, location, sentCounts) {
    try {
      const { data, error } = await this.supabase.rpc('register_user', {
        p_username: username,
        p_password: password,
        p_temp_id: tempId,
        p_gender: gender,
        p_avatar_url: avatarUrl,
        p_location: location,
        p_sent_counts: sentCounts || {}
      });

      if (error) throw error;

      if (!data.success) {
        return { success: false, error: data.error };
      }

      return { success: true, userId: data.userId };
    } catch (error) {
      console.error('注册失败:', error);
      return { success: false, error: error.message };
    }
  }

  // 更新在线状态
  async updateOnlineStatus(userId, userData) {
    try {
      const { error } = await this.supabase
        .from('online_users')
        .upsert({
          id: userId,
          username: userData.username,
          gender: userData.gender,
          avatar_url: userData.avatarUrl,
          location: userData.location,
          coins: userData.coins,
          is_temp: userData.isTemp || false,
          is_online: true,
          last_seen: new Date().toISOString()
        });

      if (error) throw error;
      return { success: true };
    } catch (error) {
      console.error('更新在线状态失败:', error);
      return { success: false, error: error.message };
    }
  }

  // 更新心跳
  async updateHeartbeat(userId) {
    try {
      const { error } = await this.supabase.rpc('update_heartbeat', {
        p_user_id: userId
      });

      if (error) throw error;
      return { success: true };
    } catch (error) {
      console.error('心跳更新失败:', error);
      return { success: false };
    }
  }

  // 设置离线状态
  async setOffline(userId) {
    try {
      const { error } = await this.supabase
        .from('online_users')
        .update({
          is_online: false,
          last_seen: new Date().toISOString()
        })
        .eq('id', userId);

      if (error) throw error;
      return { success: true };
    } catch (error) {
      console.error('设置离线失败:', error);
      return { success: false };
    }
  }

  // ==========================================
  // 2. 在线用户相关
  // ==========================================

  // 获取在线用户列表
  async getOnlineUsers() {
    try {
      const { data, error } = await this.supabase
        .from('online_users')
        .select('*')
        .eq('is_online', true)
        .order('last_seen', { ascending: false });

      if (error) throw error;
      return { success: true, users: data || [] };
    } catch (error) {
      console.error('获取在线用户失败:', error);
      return { success: false, users: [] };
    }
  }

  // 订阅在线用户变化
  subscribeToOnlineUsers(callback) {
    const channelName = 'online_users_channel';
    
    // 先获取初始数据
    this.getOnlineUsers().then(result => {
      if (result.success) {
        callback(result.users);
      }
    });

    // 订阅变化
    const channel = this.supabase
      .channel(channelName)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'online_users'
      }, async () => {
        // 有变化时重新获取
        const result = await this.getOnlineUsers();
        if (result.success) {
          callback(result.users);
        }
      })
      .subscribe();

    this.subscriptions.set(channelName, channel);
    
    return () => {
      channel.unsubscribe();
      this.subscriptions.delete(channelName);
    };
  }

  // ==========================================
  // 3. 消息相关
  // ==========================================

  // 发送消息（带限制检查）
  async sendMessage(senderId, receiverId, text, isTemp = false) {
    try {
      const { data, error } = await this.supabase.rpc('send_message_with_limits', {
        p_sender_id: senderId,
        p_receiver_id: receiverId,
        p_text: text,
        p_is_temp: isTemp
      });

      if (error) throw error;

      if (!data.success) {
        return { 
          success: false, 
          error: data.error, 
          message: data.message 
        };
      }

      return {
        success: true,
        messageId: data.messageId,
        remainingCoins: data.remainingCoins
      };
    } catch (error) {
      console.error('发送消息失败:', error);
      return { success: false, error: error.message };
    }
  }

  // 获取聊天消息
  async getMessages(chatId) {
    try {
      const { data, error } = await this.supabase
        .from('messages')
        .select('*')
        .eq('chat_id', chatId)
        .order('timestamp', { ascending: true });

      if (error) throw error;
      return { success: true, messages: data || [] };
    } catch (error) {
      console.error('获取消息失败:', error);
      return { success: false, messages: [] };
    }
  }

  // 订阅聊天消息
  subscribeToMessages(chatId, callback) {
    const channelName = `messages_${chatId}`;
    
    // 先获取初始消息
    this.getMessages(chatId).then(result => {
      if (result.success) {
        callback(result.messages);
      }
    });

    // 订阅新消息
    const channel = this.supabase
      .channel(channelName)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages',
        filter: `chat_id=eq.${chatId}`
      }, (payload) => {
        // 有新消息时，重新获取全部
        this.getMessages(chatId).then(result => {
          if (result.success) {
            callback(result.messages);
          }
        });
      })
      .subscribe();

    this.subscriptions.set(channelName, channel);
    
    return () => {
      channel.unsubscribe();
      this.subscriptions.delete(channelName);
    };
  }

  // 标记消息已读
  async markMessageAsRead(messageId) {
    try {
      const { error } = await this.supabase
        .from('messages')
        .update({ read: true })
        .eq('id', messageId);

      if (error) throw error;
      return { success: true };
    } catch (error) {
      console.error('标记已读失败:', error);
      return { success: false };
    }
  }

  // ==========================================
  // 4. 充值相关
  // ==========================================

  // 充值金币
  async rechargeCoins(userId, orderId, coins, amount) {
    try {
      const { data, error } = await this.supabase.rpc('recharge_coins', {
        p_user_id: userId,
        p_order_id: orderId,
        p_coins: coins,
        p_amount: amount
      });

      if (error) throw error;

      if (!data.success) {
        return { success: false, error: data.error };
      }

      return { success: true, newBalance: data.newBalance };
    } catch (error) {
      console.error('充值失败:', error);
      return { success: false, error: error.message };
    }
  }

  // ==========================================
  // 5. 管理员相关
  // ==========================================

  // 管理员登录
  async adminLogin(username, password) {
    try {
      const { data, error } = await this.supabase.rpc('admin_login', {
        p_username: username,
        p_password: password
      });

      if (error) throw error;

      if (!data.success) {
        return { success: false, error: data.error };
      }

      return { success: true, admin: data.admin };
    } catch (error) {
      console.error('管理员登录失败:', error);
      return { success: false, error: error.message };
    }
  }

  // 获取所有用户
  async getAllUsers() {
    try {
      const { data, error } = await this.supabase
        .from('users')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      return { success: true, users: data || [] };
    } catch (error) {
      console.error('获取用户列表失败:', error);
      return { success: false, users: [] };
    }
  }

  // 封禁/解封用户
  async banUser(userId, banned) {
    try {
      const { data, error } = await this.supabase.rpc('ban_user', {
        p_user_id: userId,
        p_banned: banned
      });

      if (error) throw error;

      if (!data.success) {
        return { success: false, error: '操作失败' };
      }

      return { success: true };
    } catch (error) {
      console.error('封禁操作失败:', error);
      return { success: false, error: error.message };
    }
  }

  // 修改用户金币
  async updateUserCoins(userId, coins) {
    try {
      const { data, error } = await this.supabase.rpc('admin_update_coins', {
        p_user_id: userId,
        p_coins: coins
      });

      if (error) throw error;

      if (!data.success) {
        return { success: false };
      }

      return { success: true };
    } catch (error) {
      console.error('更新金币失败:', error);
      return { success: false };
    }
  }

  // 获取统计数据
  async getStats() {
    try {
      const { data, error } = await this.supabase.rpc('get_stats');

      if (error) throw error;
      return { success: true, stats: data };
    } catch (error) {
      console.error('获取统计失败:', error);
      return { success: false, stats: {} };
    }
  }

  // 订阅用户列表变化
  subscribeToUsers(callback) {
    const channelName = 'users_channel';
    
    // 先获取初始数据
    this.getAllUsers().then(result => {
      if (result.success) {
        callback(result.users);
      }
    });

    // 订阅变化
    const channel = this.supabase
      .channel(channelName)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'users'
      }, async () => {
        const result = await this.getAllUsers();
        if (result.success) {
          callback(result.users);
        }
      })
      .subscribe();

    this.subscriptions.set(channelName, channel);
    
    return () => {
      channel.unsubscribe();
      this.subscriptions.delete(channelName);
    };
  }

  // ==========================================
  // 6. 工具方法
  // ==========================================

  // 生成chat_id
  generateChatId(userId1, userId2) {
    return [userId1, userId2].sort().join('_');
  }

  // 取消所有订阅
  unsubscribeAll() {
    this.subscriptions.forEach((channel, name) => {
      channel.unsubscribe();
    });
    this.subscriptions.clear();
  }
}

// ==========================================
// LocalSession 保持不变
// ==========================================

const LocalSession = {
  key: 'chat_user_session',
  
  save(session) {
    try {
      localStorage.setItem(this.key, JSON.stringify(session));
    } catch (error) {
      console.error('保存session失败:', error);
    }
  },
  
  get() {
    try {
      const data = localStorage.getItem(this.key);
      return data ? JSON.parse(data) : null;
    } catch (error) {
      console.error('获取session失败:', error);
      return null;
    }
  },
  
  clear() {
    try {
      localStorage.removeItem(this.key);
    } catch (error) {
      console.error('清除session失败:', error);
    }
  }
};

// ==========================================
// 导出（用于HTML中引用）
// ==========================================

if (typeof window !== 'undefined') {
  window.SupabaseAdapter = SupabaseAdapter;
  window.initSupabase = initSupabase;
  window.LocalSession = LocalSession;
}

// ==========================================
// 使用示例
// ==========================================

/*
// 1. 在HTML中引入SDK和配置
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="config.js"></script>
<script src="supabase-adapter.js"></script>

// 2. 初始化
const supabase = initSupabase(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey);
const db = new SupabaseAdapter(supabase);

// 3. 使用
// 登录
const result = await db.loginUser('username', 'password', 'Beijing');
if (result.success) {
  console.log('登录成功:', result.user);
}

// 发送消息
const msg = await db.sendMessage(userId, targetId, 'Hello!');
if (msg.success) {
  console.log('消息已发送');
}

// 订阅在线用户
const unsubscribe = db.subscribeToOnlineUsers((users) => {
  console.log('在线用户:', users);
  setOnlineUsers(users);
});

// 清理订阅
unsubscribe();
*/
