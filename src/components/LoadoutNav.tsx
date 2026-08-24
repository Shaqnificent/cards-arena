import { Link } from 'react-router-dom'

type LoadoutSection = 'ocs' | 'boons'

export function LoadoutNav({ active }: { active?: LoadoutSection }) {
  return <div className="loadout-subnav">
    <Link className="loadout-subnav-home" to="/loadout" aria-label="Back to Loadout overview">
      <span aria-hidden="true">&larr;</span>
      <span className="loadout-back-label">Back to Loadout</span>
      <span className="loadout-back-label-short">Back</span>
    </Link>
    <nav aria-label="Loadout sections">
      {active === 'ocs'
        ? <span aria-current="page">Family</span>
        : <Link to="/ocs">Family</Link>}
      {active === 'boons'
        ? <span aria-current="page">Boons</span>
        : <Link to="/boons">Boons</Link>}
    </nav>
  </div>
}
