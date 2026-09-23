import React, {useEffect, useState} from "react";
import {createRoot} from "react-dom/client";
import "./style.css";

const API = import.meta.env.VITE_API_URL || "/api";

function App() {
  const [orders,setOrders] = useState([]);
  const [stats,setStats] = useState({});
  const [form,setForm] = useState({customer:"",product:"",quantity:1});
  const [message,setMessage] = useState("");

  async function load() {
    const [a,b] = await Promise.all([
      fetch(`${API}/orders`),
      fetch(`${API}/stats`)
    ]);
    setOrders(await a.json()); setStats(await b.json());
  }
  useEffect(()=>{ load().catch(e=>setMessage(e.message)); },[]);

  async function submit(e) {
    e.preventDefault(); setMessage("");
    const r = await fetch(`${API}/orders`, {
      method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(form)
    });
    const data = await r.json();
    if(!r.ok){setMessage(data.error || "Failed"); return;}
    setForm({customer:"",product:"",quantity:1});
    setMessage(`Order #${data.id} created`);
    await load();
  }

  async function status(id,status) {
    await fetch(`${API}/orders/${id}/status`, {
      method:"PATCH", headers:{"Content-Type":"application/json"}, body:JSON.stringify({status})
    });
    await load();
  }

  return <div className="page">
    <header><div><h1>Northstar Orders</h1><p>Production-style order management demo</p></div><span className="pill">DevOps Lab</span></header>
    <section className="cards">
      {["CREATED","PROCESSING","SHIPPED","CANCELLED"].map(s=><div className="card" key={s}><small>{s}</small><strong>{stats[s]||0}</strong></div>)}
    </section>
    <main>
      <section className="panel">
        <h2>Create order</h2>
        <form onSubmit={submit}>
          <input required placeholder="Customer" value={form.customer} onChange={e=>setForm({...form,customer:e.target.value})}/>
          <input required placeholder="Product" value={form.product} onChange={e=>setForm({...form,product:e.target.value})}/>
          <input required type="number" min="1" value={form.quantity} onChange={e=>setForm({...form,quantity:e.target.value})}/>
          <button>Create order</button>
        </form>
        {message && <p className="message">{message}</p>}
      </section>
      <section className="panel">
        <div className="row"><h2>Recent orders</h2><button className="secondary" onClick={load}>Refresh</button></div>
        <div className="tableWrap"><table><thead><tr><th>ID</th><th>Customer</th><th>Product</th><th>Qty</th><th>Status</th><th>Action</th></tr></thead>
        <tbody>{orders.map(o=><tr key={o.id}><td>#{o.id}</td><td>{o.customer}</td><td>{o.product}</td><td>{o.quantity}</td><td><span className={`status ${o.status.toLowerCase()}`}>{o.status}</span></td><td>
          <select value={o.status} onChange={e=>status(o.id,e.target.value)}>
            {["CREATED","PROCESSING","SHIPPED","CANCELLED"].map(s=><option key={s}>{s}</option>)}
          </select>
        </td></tr>)}</tbody></table></div>
      </section>
    </main>
    <footer>React • Flask • PostgreSQL • Docker • Kubernetes • AWS • GitOps • Observability</footer>
  </div>
}
createRoot(document.getElementById("root")).render(<App/>);
