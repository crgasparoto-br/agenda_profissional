import Link from "next/link";

export default function HomePage() {
  return (
    <section className="card col">
      <h1>Agenda Profissional</h1>
      <p>Base MVP pronta para configuracao inicial, clientes e agendamentos.</p>
      <div className="row">
        <Link href="/login">Ir para login</Link>
        <Link href="/dashboard">Ir para painel</Link>
      </div>
    </section>
  );
}

