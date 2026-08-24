import { useState } from 'react'
import { resolveFamilyLogoSrc } from '../services/ocFamilyIdentity'

interface FamilyLogoProps {
  logoPath: string | null
  name: string
  updatedAt?: string | null
  className?: string
}

export function FamilyLogo({ logoPath, name, updatedAt, className = '' }: FamilyLogoProps) {
  const imageSrc = resolveFamilyLogoSrc(logoPath, updatedAt)
  const [failedSrc, setFailedSrc] = useState<string | null>(null)

  return <div className={`family-logo ${className}`.trim()}>
    {imageSrc && imageSrc !== failedSrc
      ? <img src={imageSrc} alt={`${name} family logo`} onError={() => setFailedSrc(imageSrc)} />
      : <span aria-hidden="true">{getInitials(name)}</span>}
  </div>
}

function getInitials(name: string): string {
  const initials = name.trim().split(/\s+/).filter(Boolean).slice(0, 2).map((word) => word.charAt(0).toUpperCase()).join('')
  return initials || 'OC'
}
