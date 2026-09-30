#include "RTSUnit.h"
#include "DrawDebugHelpers.h"
#include "EngineUtils.h"

ARTSUnit::ARTSUnit()
{
	Radius = 30.f;
	MaxHealth = 100.f;
	Mesh->SetWorldScale3D(FVector(0.6f, 0.6f, 1.f));
}

void ARTSUnit::OrderMove(const FVector& Dest)
{
	Target.Reset();
	Goal = Dest;
	bHasGoal = true;
	bAttackMove = false;
}

void ARTSUnit::OrderAttack(ARTSEntity* Enemy)
{
	Target = Enemy;
	bHasGoal = false;
}

void ARTSUnit::OrderAttackMove(const FVector& Dest)
{
	Target.Reset();
	Goal = Dest;
	bHasGoal = true;
	bAttackMove = true;
}

ARTSEntity* ARTSUnit::FindEnemy() const
{
	ARTSEntity* Best = nullptr;
	float BestDist = Sight;
	for (TActorIterator<ARTSEntity> It(GetWorld()); It; ++It)
	{
		ARTSEntity* E = *It;
		if (E == this || E->Team == Team || !E->IsAlive())
		{
			continue;
		}
		const float D = FVector::Dist2D(GetActorLocation(), E->GetActorLocation());
		if (D < BestDist)
		{
			BestDist = D;
			Best = E;
		}
	}
	return Best;
}

void ARTSUnit::MoveToward(const FVector& Point, float DeltaTime)
{
	FVector D = Point - GetActorLocation();
	D.Z = 0.f;
	const float Len = D.Size();
	if (Len < 1.f)
	{
		return;
	}
	const FVector Dir = D / Len;
	SetActorLocation(GetActorLocation() + Dir * FMath::Min(Speed * DeltaTime, Len));
	SetActorRotation(Dir.Rotation());
}

void ARTSUnit::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	AcquireTimer -= DeltaTime;
	CooldownLeft -= DeltaTime;

	if (!Target.IsValid() || !Target->IsAlive())
	{
		Target.Reset();
	}
	if (!Target.IsValid() && (!bHasGoal || bAttackMove) && AcquireTimer <= 0.f)
	{
		AcquireTimer = 0.4f;
		Target = FindEnemy();
	}

	if (Target.IsValid())
	{
		const FVector TargetLoc = Target->GetActorLocation();
		const float Dist = FVector::Dist2D(GetActorLocation(), TargetLoc) - Target->Radius;
		if (Dist <= Range)
		{
			FVector Face = TargetLoc - GetActorLocation();
			Face.Z = 0.f;
			SetActorRotation(Face.Rotation());
			if (CooldownLeft <= 0.f)
			{
				CooldownLeft = Cooldown;
				DrawDebugLine(GetWorld(), GetActorLocation(), TargetLoc, FColor::Yellow, false, 0.12f, 0, 5.f);
				Target->ReceiveHit(Damage);
			}
		}
		else
		{
			MoveToward(TargetLoc, DeltaTime);
		}
	}
	else if (bHasGoal)
	{
		MoveToward(Goal, DeltaTime);
		if (FVector::Dist2D(GetActorLocation(), Goal) < 20.f)
		{
			bHasGoal = false;
			bAttackMove = false;
		}
	}
}
