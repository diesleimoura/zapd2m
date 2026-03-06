import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ success: false, error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const LOVABLE_API_KEY = Deno.env.get("LOVABLE_API_KEY");
    if (!LOVABLE_API_KEY) throw new Error("LOVABLE_API_KEY is not configured");

    // Verify user
    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: authUser }, error: authError } = await userClient.auth.getUser();
    if (authError || !authUser) {
      return new Response(JSON.stringify({ success: false, error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const user = { id: authUser.id };

    const { document_id } = await req.json();
    if (!document_id) {
      return new Response(JSON.stringify({ success: false, error: "document_id required" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Get document metadata
    const { data: doc, error: docError } = await adminClient
      .from("kb_documents")
      .select("*")
      .eq("id", document_id)
      .single();

    if (docError || !doc) {
      return new Response(JSON.stringify({ success: false, error: "Document not found" }), {
        status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Verify user belongs to the tenant
    const { data: isMember } = await adminClient.rpc("is_tenant_member", {
      _user_id: user.id,
      _tenant_id: doc.tenant_id,
    });
    if (!isMember) {
      return new Response(JSON.stringify({ success: false, error: "Forbidden" }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Update status to processing
    await adminClient.from("kb_documents").update({ processing_status: "processing" }).eq("id", document_id);

    // Download file from storage
    const { data: fileData, error: downloadError } = await adminClient.storage
      .from("knowledge-base")
      .download(doc.file_path);

    if (downloadError || !fileData) {
      await adminClient.from("kb_documents").update({ processing_status: "error" }).eq("id", document_id);
      return new Response(JSON.stringify({ success: false, error: "Failed to download file" }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Determine mime type
    const ext = doc.file_name.split(".").pop()?.toLowerCase() || "";
    const textExts = ["txt", "md", "json", "csv", "xml", "yaml", "yml"];
    const isTextFile = textExts.includes(ext);

    let extractedContent = "";

    if (isTextFile) {
      // Text files: read content directly, no AI needed
      extractedContent = await fileData.text();
    } else {
      // Binary files (PDF, images): use AI extraction
      const arrayBuffer = await fileData.arrayBuffer();
      const bytes = new Uint8Array(arrayBuffer);
      let binary = "";
      for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
      }
      const base64 = btoa(binary);

      const mimeMap: Record<string, string> = {
        pdf: "application/pdf",
        png: "image/png",
        jpg: "image/jpeg",
        jpeg: "image/jpeg",
      };
      const mimeType = mimeMap[ext] || "application/octet-stream";

      // Call AI to extract text
      const aiResponse = await fetch("https://ai.gateway.lovable.dev/v1/chat/completions", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${LOVABLE_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "google/gemini-3-flash-preview",
          messages: [
            {
              role: "system",
              content: "You are a document text extractor. Extract ALL text content from the provided document. Return ONLY the extracted text, preserving the original structure (headers, lists, paragraphs). Do not add commentary or explanations. If it's a menu/price list, preserve all items and prices. If it's a FAQ, preserve all questions and answers.",
            },
            {
              role: "user",
              content: [
                {
                  type: "image_url",
                  image_url: { url: `data:${mimeType};base64,${base64}` },
                },
                {
                  type: "text",
                  text: `Extract all text content from this ${doc.doc_type} document titled "${doc.title}". Return the complete text.`,
                },
              ],
            },
          ],
        }),
      });

      if (!aiResponse.ok) {
        const errText = await aiResponse.text();
        console.error("AI extraction error:", aiResponse.status, errText);
        await adminClient.from("kb_documents").update({ processing_status: "error" }).eq("id", document_id);

        if (aiResponse.status === 429) {
          return new Response(JSON.stringify({ success: false, error: "Rate limit exceeded, try again later" }), {
            status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        if (aiResponse.status === 402) {
          return new Response(JSON.stringify({ success: false, error: "AI credits exhausted" }), {
            status: 402, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        return new Response(JSON.stringify({ success: false, error: "AI extraction failed" }), {
          status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const aiData = await aiResponse.json();
      extractedContent = aiData.choices?.[0]?.message?.content || "";
    }

    // Save extracted content
    await adminClient.from("kb_documents").update({
      content: extractedContent,
      processing_status: "completed",
    }).eq("id", document_id);

    return new Response(JSON.stringify({ success: true, data: { content_length: extractedContent.length } }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("process-document error:", e);
    return new Response(JSON.stringify({ success: false, error: e instanceof Error ? e.message : "Internal error" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
