import { Link } from 'react-router-dom'

type LoadoutSection = 'ocs' | 'boons'

export function LoadoutNav({ active }: { active?: LoadoutSection }) {
  return <div className="loadout-subnav">
    <Link className="loadout-subnav-home" to="/loadout">Loadout</Link>
    <nav aria-label="Loadout sections">
      {active === 'ocs'
        ? <span aria-current="page">OC Family</span>
        : <Link to="/ocs">OC Family</Link>}
      {active === 'boons'
        ? <span aria-current="page">Boons</span>
        : <Link to="/boons">Boons</Link>}
    </nav>
  </div>
}
