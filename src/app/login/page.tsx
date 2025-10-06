"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabaseClient";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<{
    title: string;
    details?: string;
  } | null>(null);

  // Si hay sesión válida, redirige a /dashboard
  useEffect(() => {
    let mounted = true;
    (async () => {
      const { data } = await supabase.auth.getSession();
      if (!mounted) return;
      if (data.session) {
        router.replace("/dashboard");
      }
    })();
    return () => {
      mounted = false;
    };
  }, [router]);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (error) {
        // Mostrar en español y mantener detalle técnico
        setError({
          title: "No se pudo iniciar sesión. Revisa tus credenciales.",
          details: `${error.name ?? "AuthError"} — ${error.message}`,
        });
        setLoading(false);
        return;
      }
      if (data.session) {
        router.replace("/dashboard");
      } else {
        setError({ title: "No se obtuvo sesión. Intenta nuevamente." });
        setLoading(false);
      }
    } catch (err: any) {
      setError({
        title: "Error inesperado al iniciar sesión.",
        details: String(err?.message ?? err),
      });
      setLoading(false);
    }
  };

  return (
    <div className="mx-auto max-w-sm py-10">
      <h1 className="text-2xl font-semibold mb-6">Ingresar</h1>
      <form onSubmit={handleLogin} className="space-y-4">
        <div className="space-y-1">
          <label className="block text-sm">Email</label>
          <input
            type="email"
            className="w-full border rounded px-3 py-2"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
        </div>
        <div className="space-y-1">
          <label className="block text-sm">Contraseña</label>
          <input
            type="password"
            className="w-full border rounded px-3 py-2"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </div>
        {error && (
          <div className="rounded border border-red-300 bg-red-50 p-3 text-sm">
            <div className="font-medium">⚠️ {error.title}</div>
            {error.details && (
              <details className="mt-1">
                <summary>Ver detalles técnicos</summary>
                <pre className="text-xs whitespace-pre-wrap">
                  {error.details}
                </pre>
              </details>
            )}
          </div>
        )}
        <button
          type="submit"
          className="w-full rounded bg-black text-white py-2 disabled:opacity-50"
          disabled={loading}
        >
          {loading ? "Ingresando…" : "Ingresar"}
        </button>
      </form>
    </div>
  );
}
