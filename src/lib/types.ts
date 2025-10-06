/** Enums reflejando catálogos de BD (resumen) */
export type movimiento_tipo = "ingreso" | "traslado" | "devolucion" | "baja";
export type lugar_operacion =
  | "centro"
  | "bodega"
  | "oficina"
  | "reparacion_externa";
export type movimiento_estado =
  | "pendiente"
  | "en_transito"
  | "recibido"
  | "cancelado";
export type prestamo_estado = "activo" | "devuelto";

/** Entidades mínimas */
export type Movimiento = {
  id: string;
  tipo: movimiento_tipo;
  estado: movimiento_estado;
  created_at: string;
};

export type Prestamo = {
  id: string;
  estado: prestamo_estado;
  componente_id: string;
  fecha_prestamo: string;
  fecha_devuelto?: string | null;
};

/** Contrato RPC — F3 (congelado) */
export type RpcMovCrearParams = {
  objeto_tipo: "equipo" | "componente";
  objeto_id: string;
  origen_tipo: lugar_operacion;
  origen_detalle: string;
  destino_tipo: lugar_operacion;
  destino_detalle: string;
  nota?: string; // opcional (p.ej. bajas)
};
export type RpcMovCrearReturn = string; // uuid

// Transiciones con (id, p) — p puede ir vacío por ahora.
export type RpcMovTransitionParams = {}; // reservado para futuro

export type RpcPrestamoCrearParams = {
  componente_id: string;
  equipo_origen_id: string;
  equipo_destino_id: string;
  responsable_id: string;
  motivo: string;
};
export type RpcPrestamoCrearReturn = string; // uuid

// Préstamos (id, p) — p puede ir vacío por ahora.
export type RpcPrestamoTransitionParams = {}; // reservado para futuro
