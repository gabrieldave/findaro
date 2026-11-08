import { Pool, type QueryResultRow } from "pg";

declare global {
  var __findaroPool: Pool | undefined;
}

function databaseUrl(): string {
  const raw = process.env.DATABASE_URL;
  if (!raw) throw new Error("DATABASE_URL no configurada");
  return raw;
}

export function pool(): Pool {
  if (!global.__findaroPool) {
    global.__findaroPool = new Pool({
      connectionString: databaseUrl(),
      max: 5,
      idleTimeoutMillis: 20_000,
    });
  }
  return global.__findaroPool;
}

export async function query<T extends QueryResultRow = QueryResultRow>(
  text: string,
  params?: unknown[],
) {
  return pool().query<T>(text, params);
}
