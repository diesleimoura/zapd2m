import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Validate auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ success: false, error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Verify the user is an admin
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: authUser }, error: authError } = await userClient.auth.getUser();
    if (authError || !authUser) {
      return new Response(JSON.stringify({ success: false, error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userId = authUser.id;
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);

    // Check admin role
    const { data: roles } = await adminClient
      .from("user_roles")
      .select("role")
      .eq("user_id", userId)
      .eq("role", "admin")
      .limit(1);

    if (!roles || roles.length === 0) {
      return new Response(JSON.stringify({ success: false, error: "Forbidden" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const url = new URL(req.url);
    let action = url.searchParams.get("action") || "users";

    // Support _action from POST body for SDK compatibility
    if (req.method === "POST") {
      try {
        const clonedReq = req.clone();
        const bodyText = await clonedReq.text();
        if (bodyText) {
          const bodyJson = JSON.parse(bodyText);
          if (bodyJson._action) {
            action = bodyJson._action;
          }
        }
      } catch {}
    }

    if (action === "users") {
      // Fetch all users with profiles, tenant info, subscriptions
      const { data: profiles } = await adminClient
        .from("profiles")
        .select("user_id, full_name, phone, company, tenant_id, created_at")
        .order("created_at", { ascending: false });

      if (!profiles) {
        return new Response(JSON.stringify({ success: true, data: [] }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Get auth users for emails
      const userIds = profiles.map((p) => p.user_id);
      const { data: { users: authUsers } } = await adminClient.auth.admin.listUsers({
        perPage: 1000,
      });

      const emailMap: Record<string, string> = {};
      const lastSignInMap: Record<string, string> = {};
      for (const au of authUsers || []) {
        emailMap[au.id] = au.email || "";
        lastSignInMap[au.id] = au.last_sign_in_at || "";
      }

      // Get tenant members for instance/message counts
      const tenantIds = [...new Set(profiles.map((p) => p.tenant_id).filter(Boolean))];

      // Get instance counts per tenant
      const { data: instanceCounts } = await adminClient
        .from("whatsapp_instances")
        .select("tenant_id");

      const instanceCountMap: Record<string, number> = {};
      for (const ic of instanceCounts || []) {
        instanceCountMap[ic.tenant_id] = (instanceCountMap[ic.tenant_id] || 0) + 1;
      }

      // Get message counts per tenant
      const { data: messageCounts } = await adminClient
        .from("messages")
        .select("tenant_id");

      const messageCountMap: Record<string, number> = {};
      for (const mc of messageCounts || []) {
        messageCountMap[mc.tenant_id] = (messageCountMap[mc.tenant_id] || 0) + 1;
      }

      // Get subscriptions
      const { data: subscriptions } = await adminClient
        .from("subscriptions")
        .select("tenant_id, status, plan:plans(name)")
        .order("created_at", { ascending: false });

      const subMap: Record<string, { plan: string; status: string }> = {};
      for (const sub of subscriptions || []) {
        if (!subMap[sub.tenant_id]) {
          subMap[sub.tenant_id] = {
            plan: (sub.plan as any)?.name || "Sem plano",
            status: sub.status,
          };
        }
      }

      const users = profiles.map((p) => ({
        id: p.user_id,
        name: p.full_name || "Sem nome",
        email: emailMap[p.user_id] || "",
        phone: p.phone || "",
        company: p.company || "",
        tenant_id: p.tenant_id,
        plan: subMap[p.tenant_id || ""]?.plan || "Sem plano",
        status: subMap[p.tenant_id || ""]?.status || "active",
        instances: instanceCountMap[p.tenant_id || ""] || 0,
        messages: messageCountMap[p.tenant_id || ""] || 0,
        lastActive: lastSignInMap[p.user_id] || "",
        created_at: p.created_at,
      }));

      return new Response(JSON.stringify({ success: true, data: users }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "instances") {
      const { data: instances } = await adminClient
        .from("whatsapp_instances")
        .select("*, tenant:tenants(name)")
        .order("created_at", { ascending: false });

      // Get message counts per instance (last 24h)
      const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
      const { data: recentMessages } = await adminClient
        .from("messages")
        .select("tenant_id")
        .gte("sent_at", yesterday);

      // Get tenant member names
      const tenantIds = [...new Set((instances || []).map((i) => i.tenant_id))];
      const { data: members } = await adminClient
        .from("profiles")
        .select("tenant_id, full_name")
        .in("tenant_id", tenantIds.length > 0 ? tenantIds : ["__none__"]);

      const tenantOwnerMap: Record<string, string> = {};
      for (const m of members || []) {
        if (m.tenant_id && !tenantOwnerMap[m.tenant_id]) {
          tenantOwnerMap[m.tenant_id] = m.full_name || "Desconhecido";
        }
      }

      const msgCountMap: Record<string, number> = {};
      for (const m of recentMessages || []) {
        msgCountMap[m.tenant_id] = (msgCountMap[m.tenant_id] || 0) + 1;
      }

      const result = (instances || []).map((inst) => ({
        id: inst.id,
        instance_name: inst.instance_name,
        phone: inst.phone || "Sem número",
        status: inst.status,
        tenant_id: inst.tenant_id,
        tenant_name: (inst.tenant as any)?.name || "—",
        user: tenantOwnerMap[inst.tenant_id] || "—",
        messages24h: msgCountMap[inst.tenant_id] || 0,
        created_at: inst.created_at,
      }));

      return new Response(JSON.stringify({ success: true, data: result }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "metrics") {
      const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

      const [
        usersRes,
        instancesRes,
        connectedRes,
        messagesRes,
        messages24hRes,
        conversationsRes,
        subscriptionsRes,
      ] = await Promise.all([
        adminClient.from("profiles").select("id", { count: "exact", head: true }),
        adminClient.from("whatsapp_instances").select("id", { count: "exact", head: true }),
        adminClient.from("whatsapp_instances").select("id", { count: "exact", head: true }).eq("status", "connected"),
        adminClient.from("messages").select("id", { count: "exact", head: true }),
        adminClient.from("messages").select("id", { count: "exact", head: true }).gte("sent_at", yesterday),
        adminClient.from("conversations").select("id", { count: "exact", head: true }),
        adminClient.from("subscriptions").select("status"),
      ]);

      // Revenue calculation
      const { data: activeSubs } = await adminClient
        .from("subscriptions")
        .select("plan:plans(price_cents)")
        .eq("status", "active");

      let monthlyRevenue = 0;
      for (const sub of activeSubs || []) {
        monthlyRevenue += (sub.plan as any)?.price_cents || 0;
      }

      // Subscription status breakdown
      const statusCounts: Record<string, number> = {};
      for (const sub of subscriptionsRes.data || []) {
        statusCounts[sub.status] = (statusCounts[sub.status] || 0) + 1;
      }

      return new Response(JSON.stringify({
        success: true,
        data: {
          totalUsers: usersRes.count || 0,
          totalInstances: instancesRes.count || 0,
          connectedInstances: connectedRes.count || 0,
          totalMessages: messagesRes.count || 0,
          messages24h: messages24hRes.count || 0,
          totalConversations: conversationsRes.count || 0,
          monthlyRevenueCents: monthlyRevenue,
          subscriptionsByStatus: statusCounts,
        },
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "update-user-status") {
      if (req.method !== "POST") {
        return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const body = await req.json();
      const { user_id, status } = body;

      if (!user_id || !status) {
        return new Response(JSON.stringify({ success: false, error: "Invalid payload" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Get user's tenant
      const { data: profile } = await adminClient
        .from("profiles")
        .select("tenant_id")
        .eq("user_id", user_id)
        .maybeSingle();

      if (profile?.tenant_id) {
        // Update subscription status
        const { error } = await adminClient
          .from("subscriptions")
          .update({ status })
          .eq("tenant_id", profile.tenant_id);

        if (error) {
          return new Response(JSON.stringify({ success: false, error: "Failed to update" }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "delete-user") {
      if (req.method !== "POST") {
        return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const body = await req.json();
      const { user_id: targetUserId } = body;

      if (!targetUserId) {
        return new Response(JSON.stringify({ success: false, error: "Invalid payload" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Don't allow deleting self
      if (targetUserId === userId) {
        return new Response(JSON.stringify({ success: false, error: "Cannot delete yourself" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Delete from auth (cascades to profiles, etc.)
      const { error } = await adminClient.auth.admin.deleteUser(targetUserId);
      if (error) {
        return new Response(JSON.stringify({ success: false, error: error.message }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "get-settings") {
      const { data, error } = await adminClient
        .from("system_settings")
        .select("*")
        .limit(1)
        .maybeSingle();

      if (error) {
        return new Response(JSON.stringify({ success: false, error: "Failed to fetch settings" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({ success: true, data }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "save-settings") {
      if (req.method !== "POST") {
        return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const body = await req.json();
      const {
        registration,
        auto_trial,
        email_notifs,
        detailed_logs,
        rate_limit,
        max_starter,
        max_pro,
        max_enterprise,
        timeout,
      } = body;

      const { data: existing } = await adminClient
        .from("system_settings")
        .select("id")
        .limit(1)
        .maybeSingle();

      if (!existing) {
        return new Response(JSON.stringify({ success: false, error: "Settings not found" }), {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { error } = await adminClient
        .from("system_settings")
        .update({
          registration: registration ?? true,
          auto_trial: auto_trial ?? true,
          email_notifs: email_notifs ?? true,
          detailed_logs: detailed_logs ?? false,
          rate_limit: parseInt(String(rate_limit)) || 1000,
          max_starter: parseInt(String(max_starter)) || 1,
          max_pro: parseInt(String(max_pro)) || 3,
          max_enterprise: parseInt(String(max_enterprise)) || 999,
          timeout: parseInt(String(timeout)) || 30,
        })
        .eq("id", existing.id);

      if (error) {
        return new Response(JSON.stringify({ success: false, error: "Failed to save settings" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "disconnect-all") {
      if (req.method !== "POST") {
        return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const evolutionUrl = Deno.env.get("EVOLUTION_API_URL");
      const evolutionKey = Deno.env.get("EVOLUTION_API_KEY");

      // Get all connected instances
      const { data: instances } = await adminClient
        .from("whatsapp_instances")
        .select("id, evolution_instance_id, status")
        .in("status", ["connected", "connecting"]);

      let disconnected = 0;
      let failed = 0;

      for (const inst of instances || []) {
        // Try Evolution API logout
        if (evolutionUrl && evolutionKey && inst.evolution_instance_id) {
          try {
            await fetch(`${evolutionUrl}/instance/logout/${inst.evolution_instance_id}`, {
              method: "DELETE",
              headers: { "apikey": evolutionKey },
            });
          } catch (e) {
            console.error(`Failed to logout ${inst.evolution_instance_id}:`, e);
            failed++;
          }
        }

        // Update DB status
        const { error } = await adminClient
          .from("whatsapp_instances")
          .update({ status: "disconnected", qr_code: null })
          .eq("id", inst.id);

        if (!error) disconnected++;
        else failed++;
      }

      return new Response(JSON.stringify({
        success: true,
        data: { disconnected, failed, total: (instances || []).length },
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "reset-cache") {
      if (req.method !== "POST") {
        return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { error } = await adminClient.rpc("notify_cache_reload");

      if (error) {
        console.error("Cache reset error:", error);
        return new Response(JSON.stringify({ success: false, error: "Failed to reset cache" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({
        success: true,
        data: { message: "Cache reset successfully" },
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "get-user-details") {
      const targetId = url.searchParams.get("user_id");
      if (!targetId) {
        return new Response(JSON.stringify({ success: false, error: "Missing user_id" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { data: profile } = await adminClient
        .from("profiles")
        .select("user_id, full_name, phone, company, bio, avatar_url, tenant_id, created_at")
        .eq("user_id", targetId)
        .maybeSingle();

      const { data: { users: authUsers } } = await adminClient.auth.admin.listUsers({ perPage: 1000 });
      const authUser = (authUsers || []).find((u) => u.id === targetId);

      const { data: userRoles } = await adminClient
        .from("user_roles")
        .select("role")
        .eq("user_id", targetId);

      const { data: tenantMember } = await adminClient
        .from("tenant_members")
        .select("role, tenant_id")
        .eq("user_id", targetId)
        .maybeSingle();

      let tenantName = "";
      let subscription = null;
      if (profile?.tenant_id) {
        const { data: tenant } = await adminClient
          .from("tenants")
          .select("name")
          .eq("id", profile.tenant_id)
          .maybeSingle();
        tenantName = tenant?.name || "";

        const { data: sub } = await adminClient
          .from("subscriptions")
          .select("status, started_at, trial_ends_at, current_period_end, plan:plans(name, price_cents)")
          .eq("tenant_id", profile.tenant_id)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        subscription = sub;
      }

      return new Response(JSON.stringify({
        success: true,
        data: {
          id: targetId,
          name: profile?.full_name || "Sem nome",
          email: authUser?.email || "",
          phone: profile?.phone || "",
          company: profile?.company || "",
          bio: profile?.bio || "",
          avatar_url: profile?.avatar_url || "",
          tenant_id: profile?.tenant_id || "",
          tenant_name: tenantName,
          created_at: profile?.created_at || "",
          last_sign_in: authUser?.last_sign_in_at || "",
          email_confirmed: !!authUser?.email_confirmed_at,
          roles: (userRoles || []).map((r) => r.role),
          tenant_role: tenantMember?.role || "",
          subscription,
        },
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "update-user-role") {
      if (req.method !== "POST") {
        return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const body = await req.json();
      const { user_id: targetUserId, role, action: roleAction } = body;

      if (!targetUserId || !role || !roleAction) {
        return new Response(JSON.stringify({ success: false, error: "Invalid payload" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      if (!["admin", "member"].includes(role)) {
        return new Response(JSON.stringify({ success: false, error: "Invalid role" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Don't allow removing own admin role
      if (targetUserId === userId && role === "admin" && roleAction === "remove") {
        return new Response(JSON.stringify({ success: false, error: "Cannot remove your own admin role" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      if (roleAction === "add") {
        const { error } = await adminClient
          .from("user_roles")
          .upsert({ user_id: targetUserId, role }, { onConflict: "user_id,role" });
        if (error) {
          return new Response(JSON.stringify({ success: false, error: error.message }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
      } else if (roleAction === "remove") {
        const { error } = await adminClient
          .from("user_roles")
          .delete()
          .eq("user_id", targetUserId)
          .eq("role", role);
        if (error) {
          return new Response(JSON.stringify({ success: false, error: error.message }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "change-user-plan") {
      if (req.method !== "POST") {
        return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const body = await req.json();
      const { user_id: targetUserId, plan_id } = body;

      if (!targetUserId || !plan_id) {
        return new Response(JSON.stringify({ success: false, error: "Invalid payload" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Get user's tenant
      const { data: profile } = await adminClient
        .from("profiles")
        .select("tenant_id")
        .eq("user_id", targetUserId)
        .maybeSingle();

      if (!profile?.tenant_id) {
        return new Response(JSON.stringify({ success: false, error: "User has no tenant" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Check if subscription exists
      const { data: existingSub } = await adminClient
        .from("subscriptions")
        .select("id")
        .eq("tenant_id", profile.tenant_id)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (existingSub) {
        const { error } = await adminClient
          .from("subscriptions")
          .update({ plan_id, status: "active" })
          .eq("id", existingSub.id);
        if (error) {
          return new Response(JSON.stringify({ success: false, error: error.message }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
      } else {
        const { error } = await adminClient
          .from("subscriptions")
          .insert({ tenant_id: profile.tenant_id, plan_id, status: "active" });
        if (error) {
          return new Response(JSON.stringify({ success: false, error: error.message }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ═══════════════════════════════════════════
    // PLANS (brief list for dropdowns)
    // ═══════════════════════════════════════════

    if (action === "list-plans-brief") {
      const { data, error } = await adminClient.from("plans").select("id, name, price_cents").order("price_cents");
      if (error) return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      return new Response(JSON.stringify({ success: true, data }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // ═══════════════════════════════════════════
    // ROADMAP (Admin CRUD)
    // ═══════════════════════════════════════════

    if (action === "roadmap-list-all") {
      const { data, error } = await adminClient.from("roadmap_items").select("*").order("sort_order", { ascending: true });
      if (error) return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      return new Response(JSON.stringify({ success: true, data }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (action === "roadmap-create") {
      const body = await req.clone().json().catch(() => ({}));
      const { title, description, status: itemStatus, icon, sort_order, visible } = body;
      const { data, error } = await adminClient.from("roadmap_items").insert({
        title: title || "Novo item", description: description || "Descrição",
        status: itemStatus || "planned", icon: icon || "Zap",
        sort_order: sort_order ?? 0, visible: visible !== false,
      }).select().single();
      if (error) return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      return new Response(JSON.stringify({ success: true, data }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (action === "roadmap-update") {
      const body = await req.clone().json().catch(() => ({}));
      const { id, ...updates } = body;
      if (!id) return new Response(JSON.stringify({ success: false, error: "id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      const allowed = ["title", "description", "status", "icon", "version", "sort_order", "visible"];
      const sanitized: Record<string, unknown> = {};
      for (const k of allowed) { if (updates[k] !== undefined) sanitized[k] = updates[k]; }
      const { error } = await adminClient.from("roadmap_items").update(sanitized).eq("id", id);
      if (error) return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (action === "roadmap-delete") {
      const body = await req.clone().json().catch(() => ({}));
      const { id } = body;
      if (!id) return new Response(JSON.stringify({ success: false, error: "id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      const { error } = await adminClient.from("roadmap_items").delete().eq("id", id);
      if (error) return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (action === "roadmap-reorder") {
      const body = await req.clone().json().catch(() => ({}));
      const { items } = body;
      if (!items || !Array.isArray(items)) return new Response(JSON.stringify({ success: false, error: "items required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      for (const item of items) {
        await adminClient.from("roadmap_items").update({ sort_order: item.sort_order }).eq("id", item.id);
      }
      return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (action === "roadmap-vote-counts") {
      const { data } = await adminClient.from("roadmap_votes").select("roadmap_item_id");
      const counts: Record<string, number> = {};
      for (const v of data || []) counts[v.roadmap_item_id] = (counts[v.roadmap_item_id] || 0) + 1;
      return new Response(JSON.stringify({ success: true, data: counts }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // ═══════════════════════════════════════════
    // FLOATING BUTTON (Admin CRUD)
    // ═══════════════════════════════════════════

    if (action === "floating-btn-get") {
      const { data } = await adminClient.from("floating_button_settings").select("*").limit(1).maybeSingle();
      return new Response(JSON.stringify({ success: true, data }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (action === "floating-btn-save") {
      const body = await req.clone().json().catch(() => ({}));
      const { id, phone, default_message, button_text, position, icon, button_color, text_color, show_text, active } = body;
      const payload = { phone, default_message, button_text, position, icon, button_color, text_color, show_text, active };
      let error;
      if (id) {
        ({ error } = await adminClient.from("floating_button_settings").update(payload).eq("id", id));
      } else {
        ({ error } = await adminClient.from("floating_button_settings").insert(payload));
      }
      if (error) return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      // Return updated data
      const { data: updated } = await adminClient.from("floating_button_settings").select("*").limit(1).maybeSingle();
      return new Response(JSON.stringify({ success: true, data: updated }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (action === "evolution-status") {
      const evolutionUrl = Deno.env.get("EVOLUTION_API_URL");
      const evolutionKey = Deno.env.get("EVOLUTION_API_KEY");

      const hasUrl = !!evolutionUrl && evolutionUrl.trim().length > 0;
      const hasKey = !!evolutionKey && evolutionKey.trim().length > 0;

      let connectionOk = false;
      let connectionError = "";

      if (hasUrl && hasKey) {
        try {
          const url = evolutionUrl!.trim().replace(/\/+$/, "");
          const res = await fetch(`${url}/instance/fetchInstances`, {
            headers: { apikey: evolutionKey!.trim() },
          });
          connectionOk = res.ok;
          if (!res.ok) connectionError = `HTTP ${res.status}`;
        } catch (e) {
          connectionError = "Connection failed";
        }
      }

      return new Response(JSON.stringify({
        success: true,
        data: {
          has_url: hasUrl,
          has_key: hasKey,
          connection_ok: connectionOk,
          connection_error: connectionError,
          base_url_masked: hasUrl ? evolutionUrl!.trim().replace(/\/+$/, "").substring(0, 30) + "..." : "",
        },
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "save-evolution") {
      if (req.method !== "POST") {
        return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Note: Secrets must be managed via Lovable Cloud secrets panel
      // This action just tests the provided credentials
      const body = await req.json();
      const { base_url, api_key } = body;

      if (!base_url || !api_key) {
        return new Response(JSON.stringify({ success: false, error: "base_url and api_key required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      try {
        const url = base_url.trim().replace(/\/+$/, "");
        const res = await fetch(`${url}/instance/fetchInstances`, {
          headers: { apikey: api_key.trim() },
        });
        if (res.ok) {
          return new Response(JSON.stringify({ success: true, data: { connection_ok: true } }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        return new Response(JSON.stringify({ success: false, error: `HTTP ${res.status}: ${res.statusText}` }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch {
        return new Response(JSON.stringify({ success: false, error: "Connection failed" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    return new Response(JSON.stringify({ success: false, error: "Unknown action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("admin-data error:", e);
    return new Response(JSON.stringify({ success: false, error: "Internal error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
