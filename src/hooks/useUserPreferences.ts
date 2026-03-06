import { useState, useEffect, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { useTheme } from "next-themes";

export interface UserPreferences {
  theme: string;
  language: string;
  ai_default_enabled: boolean;
}

const defaults: UserPreferences = {
  theme: "dark",
  language: "pt-br",
  ai_default_enabled: true,
};

const themeMap: Record<string, string> = {
  dark: "dark",
  light: "light",
  system: "system",
};

export function useUserPreferences() {
  const { user } = useAuth();
  const { setTheme } = useTheme();
  const [preferences, setPreferences] = useState<UserPreferences>(defaults);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      setLoading(true);
      const { data, error } = await supabase.functions.invoke("data-api", {
        body: { _action: "user-preferences-get" },
      });

      if (!error && data?.success && data.data) {
        const prefs = {
          theme: data.data.theme || defaults.theme,
          language: data.data.language || defaults.language,
          ai_default_enabled: data.data.ai_default_enabled ?? defaults.ai_default_enabled,
        };
        setPreferences(prefs);
        setTheme(themeMap[prefs.theme] || "dark");
      } else {
        setTheme("dark");
      }
      setLoading(false);
    };
    load();
  }, [user]);

  const update = useCallback((partial: Partial<UserPreferences>) => {
    setPreferences((prev) => {
      const next = { ...prev, ...partial };
      if (partial.theme) setTheme(themeMap[partial.theme] || "dark");
      return next;
    });
  }, [setTheme]);

  const save = useCallback(async () => {
    if (!user) return false;
    setSaving(true);
    const { data, error } = await supabase.functions.invoke("data-api", {
      body: {
        _action: "user-preferences-upsert",
        theme: preferences.theme,
        language: preferences.language,
        ai_default_enabled: preferences.ai_default_enabled,
      },
    });
    setSaving(false);
    return !error && data?.success;
  }, [user, preferences]);

  return { preferences, update, save, loading, saving };
}
