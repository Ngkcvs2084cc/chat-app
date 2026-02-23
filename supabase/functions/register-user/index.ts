// ==========================================
// Supabase Edge Function: send-message
// ==========================================
// 发送消息的安全后端逻辑
// ==========================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // 处理CORS预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. 创建Supabase客户端
    const authHeader = req.headers.get('Authorization')!
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    // 2. 验证用户身份
    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser()

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: '未登录或token已过期' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // 3. 获取请求参数
    const { targetUserId, text } = await req.json()

    // 4. 参数验证
    if (!targetUserId || !text) {
      return new Response(
        JSON.stringify({ error: '参数不完整' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (typeof text !== 'string' || text.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: '消息内容不能为空' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (text.length > 500) {
      return new Response(
        JSON.stringify({ error: '消息长度不能超过500字' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (targetUserId === user.id) {
      return new Response(
        JSON.stringify({ error: '不能给自己发消息' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // 5. 获取当前用户信息
    const { data: senderData, error: senderError } = await supabaseClient
      .from('users')
      .select('is_temp, coins')
      .eq('id', user.id)
      .single()

    if (senderError || !senderData) {
      return new Response(
        JSON.stringify({ error: '用户信息获取失败' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // 6. 获取发送次数
    const { data: countResult } = await supabaseClient.rpc('get_message_count', {
      p_user_id: user.id,
      p_target_id: targetUserId,
    })

    const sentCount = countResult || 0
    let coinsDeducted = 0

    // 7. 检查发送限制
    if (sentCount >= 5) {
      // 临时用户：拒绝
      if (senderData.is_temp) {
        return new Response(
          JSON.stringify({
            error: '临时用户已超出免费额度',
            errorCode: 'TEMP_USER_LIMIT',
            message: '请注册后继续使用',
          }),
          {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        )
      }

      // 注册用户：检查金币
      if (senderData.coins < 2) {
        return new Response(
          JSON.stringify({
            error: '金币不足',
            errorCode: 'INSUFFICIENT_COINS',
            message: '请充值后继续',
            currentCoins: senderData.coins,
          }),
          {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        )
      }

      // 扣除金币
      const { data: deductResult, error: deductError } = await supabaseClient.rpc(
        'deduct_coins',
        {
          p_user_id: user.id,
          p_amount: 2,
        }
      )

      if (deductError || !deductResult) {
        return new Response(
          JSON.stringify({ error: '扣除金币失败' }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        )
      }

      coinsDeducted = 2
    }

    // 8. 创建消息
    const chatId = [user.id, targetUserId].sort().join('_')

    const { data: newMessage, error: messageError } = await supabaseClient
      .from('messages')
      .insert({
        chat_id: chatId,
        sender_id: user.id,
        receiver_id: targetUserId,
        text: text.trim(),
      })
      .select()
      .single()

    if (messageError) {
      // 如果消息创建失败且已扣币，需要退还（这里简化处理）
      console.error('消息创建失败:', messageError)
      return new Response(
        JSON.stringify({ error: '消息发送失败，请重试' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // 9. 更新发送计数
    const { error: countError } = await supabaseClient.rpc('increment_message_count', {
      p_user_id: user.id,
      p_target_id: targetUserId,
    })

    if (countError) {
      console.error('更新计数失败:', countError)
    }

    // 10. 返回成功响应
    return new Response(
      JSON.stringify({
        success: true,
        message: newMessage,
        coinsDeducted: coinsDeducted,
        remainingCoins: senderData.coins - coinsDeducted,
        newMessageCount: sentCount + 1,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('发送消息错误:', error)
    return new Response(
      JSON.stringify({
        error: '服务器内部错误',
        message: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
