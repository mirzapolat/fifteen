import { useEffect, useState } from 'react';
import { Glass } from './Glass.jsx';

/** Assembled at runtime so the address isn't sitting in the HTML for scrapers. */
function Email() {
  const [addr, setAddr] = useState('');
  useEffect(() => setAddr(['contact', 'getfifteen.de'].join('@')), []);
  if (!addr) return <span>contact (at) getfifteen.de</span>;
  return <a href={`mailto:${addr}`}>{addr}</a>;
}

function Page({ title, de, children, go, Link }) {
  return (
    <section className="legal">
      <Link to="/" go={go} className="back">
        ← Back to Fifteen
      </Link>
      <Glass className="legal-card">
        <h1>
          {title} <span className="dim">· {de}</span>
        </h1>
        {children}
      </Glass>
    </section>
  );
}

export function Imprint(props) {
  return (
    <Page title="Imprint" de="Impressum" {...props}>
      <h2>Angaben gemäß § 5 DDG</h2>
      <address>
        Mirza Polat
        <br />
        Dachauer Str. 159
        <br />
        80636 München
        <br />
        Germany
      </address>

      <h2>Contact · Kontakt</h2>
      <p>
        Email: <Email />
      </p>

      <h2>Responsible for content · Verantwortlich für den Inhalt</h2>
      <p>Mirza Polat, address as above.</p>

      <h2>Liability for links · Haftung für Links</h2>
      <p>
        This site links to external websites (such as GitHub). I have no influence over their content and accept no
        liability for it; the respective provider is always responsible. If I become aware of any infringement, I
        will remove the link promptly.
      </p>

      <h2>Consumer dispute resolution · Verbraucherstreitbeilegung</h2>
      <p>
        I am neither willing nor obliged to take part in dispute resolution proceedings before a consumer arbitration
        board.
      </p>
    </Page>
  );
}

export function Privacy(props) {
  return (
    <Page title="Privacy" de="Datenschutz" {...props}>
      <p className="legal-lede">
        Short version: this website sets no cookies, uses no analytics or trackers, and loads no fonts or scripts from
        third parties. The Fifteen app keeps your history on your device.
      </p>

      <h2>Who is responsible</h2>
      <p>
        Mirza Polat, Dachauer Str. 159, 80636 München, Germany. Email: <Email />
      </p>

      <h2>Visiting this website</h2>
      <p>
        When you open getfifteen.de, your browser sends technical data to the server, such as your IP address, the
        date and time, the page requested, and your browser’s user agent. This is needed to deliver the page and keep
        the server secure (Art. 6 (1)(f) GDPR). The data may appear briefly in server logs and is not combined with
        other data or used to identify you.
      </p>

      <h2>Downloading Fifteen</h2>
      <p>
        The Mac download is hosted on GitHub. When you click “Download for Mac”, your browser fetches the file
        directly from GitHub, Inc. (88 Colin P. Kelly Jr. Street, San Francisco, CA 94107, USA), which receives your
        IP address and browser details to deliver it. See{' '}
        <a href="https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement" rel="noopener">
          GitHub’s privacy statement
        </a>
        . Nothing is sent to GitHub unless you click download.
      </p>

      <h2>The app</h2>
      <p>
        Fifteen has no account and no tracking. Sessions, notes and projects are stored locally on your device. If
        you use Link to focus with others, only the shared timer state (and the display name you choose) passes
        through the relay server for as long as the group exists. To keep itself up to date, the Mac app checks
        GitHub for new versions.
      </p>

      <h2>Your rights</h2>
      <p>
        You have the right to access, rectification, erasure, restriction of processing, data portability and to
        object to processing of your personal data, and the right to lodge a complaint with a supervisory authority,
        for example the Bayerisches Landesamt für Datenschutzaufsicht (BayLDA).
      </p>
    </Page>
  );
}
