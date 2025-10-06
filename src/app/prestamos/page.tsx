"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabaseClient";

export default function PrestamosNuevoPage() {
  const router = useRouter();
  useEffect(() => {
    let mounted = true;
    (async () => {
      const { data } = await supabase.auth.getSession();
      if (!mounted) return;
      if (!data.session) router.replace("/login");
    })();
    return () => {
      mounted = false;
    };
  }, [router]);

  return (
    <div className="py-6">
      <h1 className="text-xl font-semibold">Nuevo Préstamo</h1>
      <p className="text-sm text-neutral-600">Se implementará en la Etapa D.</p>
    </div>
  );
}
