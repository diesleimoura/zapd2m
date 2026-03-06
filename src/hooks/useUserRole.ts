import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export function useUserRole() {
  const { user, loading: authLoading } = useAuth();
  const [role, setRole] = useState<string | null>(null);
  const [isRoleLoading, setIsRoleLoading] = useState(true);

  useEffect(() => {
    if (authLoading) return;
    if (!user?.id) {
      setRole(null);
      setIsRoleLoading(false);
      return;
    }

    setIsRoleLoading(true);
    supabase.functions.invoke("data-api", {
      body: { _action: "user-role-get" },
    }).then(({ data, error }) => {
      if (error || !data?.success) {
        console.error("Error fetching role:", error);
        setRole(null);
      } else {
        const roles = data.data || [];
        const isAdmin = roles.some((r: any) => r.role === "admin");
        setRole(isAdmin ? "admin" : roles[0]?.role || null);
      }
      setIsRoleLoading(false);
    }).catch(() => {
      setRole(null);
      setIsRoleLoading(false);
    });
  }, [user?.id, authLoading]);

  return { role, isAdmin: role === "admin", isRoleLoading };
}