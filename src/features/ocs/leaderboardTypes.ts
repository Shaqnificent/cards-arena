export type OcLeaderboardSort = 'overall' | 'power' | 'growth'
export interface OcIndividualRank { rank:number; id:string; name:string; imageUrl:string|null; ownerId:string; ownerUsername:string; ownerAvatarUrl:string|null; verseId:number; verseName:string; startingOverall:number; overall:number; overallCap:number; powerScore:number; powerScoreCap:number; growth:number }
export interface OcFamilyPreview { id:string; name:string; verseId:number; verseName:string; startingOverall:number; overall:number; powerScore:number; growth:number }
export interface OcFamilyRank { rank:number; ownerId:string; username:string; avatarUrl:string|null; familySize:number; avgOverall:number; avgPowerScore:number; totalGrowth:number; family:OcFamilyPreview[] }
