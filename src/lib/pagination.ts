export type PaginationItem = number | `ellipsis-${number}-${number}`

export interface PaginationRangeOptions {
  currentPage: number
  totalPages: number
  siblingCount: number
}

export function getPaginationItems({
  currentPage,
  totalPages,
  siblingCount,
}: PaginationRangeOptions): PaginationItem[] {
  if (totalPages <= 0) return []

  const lastPage = Math.max(1, Math.floor(totalPages))
  const current = Math.min(lastPage, Math.max(1, Math.floor(currentPage)))
  const siblings = Math.max(0, Math.floor(siblingCount))
  const boundaryWindowSize = siblings * 2 + 1
  let rangeStart = Math.max(1, current - siblings)
  let rangeEnd = Math.min(lastPage, current + siblings)

  if (current <= siblings + 1) {
    rangeStart = 1
    rangeEnd = Math.min(lastPage, boundaryWindowSize)
  } else if (current >= lastPage - siblings) {
    rangeStart = Math.max(1, lastPage - boundaryWindowSize + 1)
    rangeEnd = lastPage
  }

  const visiblePages = new Set<number>([1, lastPage])
  for (let page = rangeStart; page <= rangeEnd; page += 1) visiblePages.add(page)

  const orderedPages = [...visiblePages].toSorted((first, second) => first - second)
  const items: PaginationItem[] = []

  for (const page of orderedPages) {
    const previousPage = items.findLast((item): item is number => typeof item === 'number')
    if (previousPage !== undefined && page - previousPage === 2) items.push(previousPage + 1)
    else if (previousPage !== undefined && page - previousPage > 2) items.push(`ellipsis-${previousPage}-${page}`)
    items.push(page)
  }

  return items
}
