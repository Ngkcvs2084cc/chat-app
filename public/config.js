// ==========================================
// Supabase 配置文件
// ==========================================

// 📝 使用说明：
// 1. 登录 Supabase Dashboard (https://supabase.com)
// 2. 进入你的项目
// 3. 点击左侧 Settings (齿轮图标) > API
// 4. 复制以下两个值：
//    - Project URL (项目URL)
//    - anon public key (匿名公钥)
// 5. 填入下方对应位置

const SUPABASE_CONFIG = {
  // 项目URL - 格式：https://你的项目ID.supabase.co
  url: 'https://pvuhfhaijgdvasfwempf.supabase.co',
  
  // 匿名公钥 - 一长串字符
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB2dWhmaGFpamdkdmFzZndlbXBmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyODU5NzYsImV4cCI6MjA4Nzg2MTk3Nn0.CgyiSoPJIaomGf6RlU31Cu6k5UKCENYmgAnkHcOs1jw'
};

// 导出配置（用于在HTML中引用）
if (typeof window !== 'undefined') {
  window.SUPABASE_CONFIG = SUPABASE_CONFIG;
}

// ==========================================
// ⚠️ 重要提示
// ==========================================
// 
// 1. 确保已在Supabase执行 complete-migration.sql
// 2. URL和Key必须正确，否则无法连接数据库
// 3. 这些信息是公开的（anon key），安全性由RLS保证
// 4. 不要将service_role_key放在前端代码中
//
// ==========================================
