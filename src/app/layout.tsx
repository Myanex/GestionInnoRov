export const metadata = {
  title: "Sistema de Gestión ROV — Frontend F3",
  description: "UI mínima operable para movimientos y préstamos.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es">
      <body className="min-h-screen bg-neutral-50 text-neutral-900">
        <div id="app-root" className="mx-auto max-w-5xl p-4">
          {children}
        </div>
      </body>
    </html>
  );
}
