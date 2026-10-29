'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useParams } from 'next/navigation';
import AppShell from '@/components/AppShell';
import { supabaseBrowser } from '@/lib/supabase';
import { Printer, ArrowLeft, Bike } from 'lucide-react';

type BillFormat = '58mm' | '80mm' | 'A4';

type Sale = {
  id: string;
  receipt_no: string;
  customer_name: string | null;
  customer_phone: string | null;
  payment_method: string;
  subtotal: number;
  discount: number;
  total_amount: number;
  created_at: string;
};

type Item = {
  id: string;
  part_name: string;
  quantity: number;
  unit_price: number;
  line_total: number;
};

const money = (amount: number) =>
  `₹${Number(amount || 0).toFixed(2)}`;

export default function ReceiptPage() {
  const { id } = useParams<{ id: string }>();

  const [sale, setSale] = useState<Sale | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [shop, setShop] = useState('Automobile Spare Parts');
const [format, setFormat] = useState<BillFormat>(() => {
  if (typeof window === 'undefined') return '58mm';

  const saved = localStorage.getItem('bikespare-bill-format');

  if (saved === '58mm' || saved === '80mm' || saved === 'A4') {
    return saved;
  }

  return '58mm';
});  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;

    async function loadReceipt() {
      try {
        const sb = supabaseBrowser();

        const { data: saleData, error: saleError } = await sb
          .from('sales')
          .select('*')
          .eq('id', id)
          .single();

        if (saleError) throw saleError;

        const { data: itemData, error: itemError } = await sb
          .from('sale_items')
          .select('*')
          .eq('sale_id', id);

        if (itemError) throw itemError;

        const {
          data: { user },
        } = await sb.auth.getUser();

        let shopName = 'Automobile Spare Parts';

        if (user) {
          const { data: profile } = await sb
            .from('profiles')
            .select('shops(name)')
            .eq('id', user.id)
            .maybeSingle();

          const profileData = profile as {
            shops?: { name?: string } | null;
          } | null;

          if (profileData?.shops?.name) {
            shopName = profileData.shops.name;
          }
        }

        if (active) {
          setSale(saleData as Sale);
          setItems((itemData || []) as Item[]);
          setShop(shopName);
        }
      } catch (err) {
        if (active) {
          setError(
            err instanceof Error
              ? err.message
              : 'Unable to load receipt.'
          );
        }
      } finally {
        if (active) setLoading(false);
      }
    }

    loadReceipt();

    return () => {
      active = false;
    };
  }, [id]);

  function printReceipt() {
    window.print();
  }

  return (
    <AppShell>
      <div className={`content receipt-page format-${format}`}>
        <div className="page-head no-print">
          <div>
            <div className="eyebrow">CUSTOMER RECEIPT</div>
            <h1>Sale receipt</h1>
            <p>Choose a paper size and print your bill.</p>
          </div>

          <Link className="btn btn-light" href="/sales/history">
            <ArrowLeft size={15} />
            History
          </Link>
        </div>

        <div className="receipt-controls no-print">
          <label htmlFor="bill-format">Bill format</label>

          <select
  id="bill-format"
  value={format}
  onChange={(event) => {
    const selected = event.target.value as BillFormat;
    setFormat(selected);
    localStorage.setItem('bikespare-bill-format', selected);
  }}
>
  <option value="58mm">Thermal receipt — 58mm</option>
  <option value="80mm">Thermal receipt — 80mm</option>
  <option value="A4">Regular invoice — A4</option>
</select>

          <button
            className="btn btn-primary"
            onClick={printReceipt}
            disabled={loading || !sale}
          >
            <Printer size={16} />
            Print bill
          </button>
        </div>

        {error && <div className="alert alert-error">{error}</div>}

        {loading ? (
          <div className="loading">Loading receipt…</div>
        ) : sale ? (
          <div className={`receipt printable-receipt receipt-${format}`}>
            <header className="bill-header">
              <div className="bill-shop">
                <Bike size={format === 'A4' ? 25 : 20} />
                <h2>{shop}</h2>
              </div>

              <p className="bill-subtitle">
                AUTOMOBILE SPARE PARTS &amp; SERVICE
              </p>

              {format === 'A4' && <h3>SALES INVOICE</h3>}
            </header>

            <div className="bill-divider" />

            <section className="bill-info">
              <div>
                <span>Bill No.</span>
                <strong>{sale.receipt_no}</strong>
              </div>

              <div>
                <span>Date</span>
                <strong>
                  {new Date(sale.created_at).toLocaleDateString('en-IN')}
                </strong>
              </div>

              <div>
                <span>Time</span>
                <strong>
                  {new Date(sale.created_at).toLocaleTimeString('en-IN', {
                    hour: '2-digit',
                    minute: '2-digit',
                  })}
                </strong>
              </div>
            </section>

            <div className="bill-divider" />

            <section className="bill-customer">
              <span>Customer</span>
              <strong>
                {sale.customer_name || 'Walk-in customer'}
              </strong>

              {sale.customer_phone && (
                <div>{sale.customer_phone}</div>
              )}
            </section>

            <div className="bill-divider" />

            <table className="bill-items">
              <thead>
                <tr>
                  <th>Item</th>
                  <th>Qty</th>
                  <th>Price</th>
                  <th className="bill-amount">Amount</th>
                </tr>
              </thead>

              <tbody>
                {items.map((item) => (
                  <tr key={item.id}>
                    <td className="bill-item-name">
                      {item.part_name}
                    </td>
                    <td>{item.quantity}</td>
                    <td>{money(item.unit_price)}</td>
                    <td className="bill-amount">
                      {money(item.line_total)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <div className="bill-divider" />

            <section className="bill-totals">
              <div>
                <span>Subtotal</span>
                <strong>{money(sale.subtotal)}</strong>
              </div>

              <div>
                <span>Discount</span>
                <strong>
                  - {money(sale.discount)}
                </strong>
              </div>

              <div className="bill-grand-total">
                <span>TOTAL</span>
                <strong>{money(sale.total_amount)}</strong>
              </div>
            </section>

            <div className="bill-divider" />

            <section className="bill-payment">
              <span>Payment method</span>
              <strong>{sale.payment_method}</strong>
            </section>

            <footer className="bill-footer">
              <strong>Thank you for your business!</strong>
              <p>Please visit again.</p>
              <small>
                Software by{' '}
                {process.env.NEXT_PUBLIC_DEVELOPER_NAME || 'Sumit Kaware'}
                {' · '}
                {process.env.NEXT_PUBLIC_DEVELOPER_PHONE || '83xxxxxxxx'}
              </small>
            </footer>
          </div>
        ) : null}
      </div>
    </AppShell>
  );
}