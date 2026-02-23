// build.js - 构建脚本，替换环境变量
const fs = require('fs');
const path = require('path');

console.log('🔨 开始构建...');

// 读取HTML文件
const htmlPath = path.join(__dirname, 'public', 'index.html');
let html = fs.readFileSync(htmlPath, 'utf8');

// 从环境变量获取配置
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || 'YOUR_SUPABASE_URL';
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'YOUR_SUPABASE_KEY';

console.log('📝 配置信息:');
console.log(`   Supabase URL: ${supabaseUrl.substring(0, 30)}...`);
console.log(`   Supabase Key: ${supabaseKey.substring(0, 30)}...`);

// 替换占位符
html = html.replace('YOUR_SUPABASE_URL', supabaseUrl);
html = html.replace('YOUR_SUPABASE_KEY', supabaseKey);

// 创建构建目录
const buildDir = path.join(__dirname, 'build');
if (!fs.existsSync(buildDir)) {
    fs.mkdirSync(buildDir, { recursive: true });
}

// 写入构建文件
const outputPath = path.join(buildDir, 'index.html');
fs.writeFileSync(outputPath, html);

console.log('✅ 构建完成！');
console.log(`📁 输出文件: ${outputPath}`);
