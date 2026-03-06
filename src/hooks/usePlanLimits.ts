import { useState, useEffect, useCallback, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export interface PlanLimits {
  max_instances: number;
  max_messages: number | null;
  max_bots: number;
  max_users: number;
  storage_mb: number;
}

export interface PlanUsage {
  instances: number;
  members: number;
  messages_this_month: number;
  bots: number;
  storage_mb: number;
}

export interface PlanInfo {
  id: string;
  name: string;
  price_cents: number;
  max_instances: number;
  max_messages: number | null;
  max_bots: number;
  max_users: number;
  storage_mb: number;
  support_level: string;
}

export interface SubscriptionInfo {
  id: string;
  status: string;
  trial_ends_at: string | null;
  current_period_end: string | null;
}

export function usePlanLimits() {
  const { user } = useAuth();
  const userId = user?.id;
  const [loading, setLoading] = useState(true);
  const [hasPlan, setHasPlan] = useState(false);
  const [plan, setPlan] = useState<PlanInfo | null>(null);
  const [subscription, setSubscription] = useState<SubscriptionInfo | null>(null);
  const [usage, setUsage] = useState<PlanUsage | null>(null);
  const [trialBlocked, setTrialBlocked] = useState(false);
  const [trialDaysLeft, setTrialDaysLeft] = useState<number | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const fetchedRef = useRef<string | null>(null);

  const applyData = (data: any) => {
    setHasPlan(data.has_plan);
    setPlan(data.plan || null);
    setSubscription(data.subscription || null);
    setUsage(data.usage || null);
    setTrialBlocked(!!data.trial_blocked);
    setTrialDaysLeft(data.trial_days_left ?? null);
    setIsAdmin(!!data.is_admin);
  };

  useEffect(() => {
    if (!userId) {
      setTrialBlocked(false);
      setIsAdmin(false);
      setTrialDaysLeft(null);
      setLoading(false);
      return;
    }
    if (fetchedRef.current === userId) return;
    fetchedRef.current = userId;

    let cancelled = false;
    const doFetch = async () => {
      setLoading(true);
      try {
        const { data, error } = await supabase.functions.invoke("check-plan-limits", {
          method: "POST",
          body: {},
        });
        if (cancelled) return;
        if (!error && data?.success && data.data) {
          applyData(data.data);
        }
      } catch (e) {
        console.error("Failed to fetch plan limits:", e);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    doFetch();
    return () => { cancelled = true; };
  }, [userId]);

  const refetch = useCallback(async () => {
    if (!userId) return;
    fetchedRef.current = null;
    setLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke("check-plan-limits", {
        method: "POST",
        body: {},
      });
      if (!error && data?.success && data.data) {
        applyData(data.data);
      }
    } catch (e) {
      console.error("Failed to fetch plan limits:", e);
    } finally {
      setLoading(false);
      fetchedRef.current = userId;
    }
  }, [userId]);

  const canCreateInstance = (): boolean => {
    if (isAdmin) return true;
    if (trialBlocked || !plan || !usage) return false;
    return usage.instances < plan.max_instances;
  };

  const canSendMessage = (): boolean => {
    if (isAdmin) return true;
    if (trialBlocked || !plan || !usage) return false;
    if (plan.max_messages === null) return true;
    return usage.messages_this_month < plan.max_messages;
  };

  const canAddUser = (): boolean => {
    if (isAdmin) return true;
    if (!plan || !usage) return false;
    return usage.members < plan.max_users;
  };

  const canAddBot = (): boolean => {
    if (isAdmin) return true;
    if (!plan || !usage) return false;
    return usage.bots < plan.max_bots;
  };

  const canUploadStorage = (additionalMb: number = 0): boolean => {
    if (isAdmin) return true;
    if (!plan || !usage) return false;
    return (usage.storage_mb + additionalMb) <= plan.storage_mb;
  };

  const getUsagePercent = (key: "instances" | "messages" | "members" | "bots" | "storage"): number => {
    if (!plan || !usage) return 0;
    switch (key) {
      case "instances": return Math.round((usage.instances / plan.max_instances) * 100);
      case "messages": return plan.max_messages ? Math.round((usage.messages_this_month / plan.max_messages) * 100) : 0;
      case "members": return Math.round((usage.members / plan.max_users) * 100);
      case "bots": return Math.round((usage.bots / plan.max_bots) * 100);
      case "storage": return Math.round((usage.storage_mb / plan.storage_mb) * 100);
      default: return 0;
    }
  };

  return {
    loading,
    hasPlan,
    trialBlocked,
    trialDaysLeft,
    isAdmin,
    plan,
    subscription,
    usage,
    refetch,
    canCreateInstance,
    canSendMessage,
    canAddUser,
    canAddBot,
    canUploadStorage,
    getUsagePercent,
  };
}
