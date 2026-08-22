import { useState } from 'react'
import { resolveOcImageSrc } from '../services/ocImageUrl'

export function OCImage({ src, name, className = '' }: { src: string | null; name: string; className?: string }) {
  const [failedSrc, setFailedSrc] = useState<string | null>(null)
  const imageSrc = resolveOcImageSrc(src)
  return <div className={`oc-image ${className}`}>
    {imageSrc && failedSrc !== imageSrc ? <img src={imageSrc} alt={`${name} portrait`} onError={() => setFailedSrc(imageSrc)} /> : <span aria-hidden="true">{name.trim().charAt(0).toUpperCase() || '?'}</span>}
  </div>
}
