#include "RTSController.h"
#include "RTSUnit.h"
#include "RTSCameraPawn.h"
#include "RTSGameMode.h"
#include "EngineUtils.h"

void ARTSController::BeginPlay()
{
	Super::BeginPlay();
	bShowMouseCursor = true;
	FInputModeGameAndUI Mode;
	Mode.SetLockMouseToViewportBehavior(EMouseLockMode::LockAlways);
	Mode.SetHideCursorDuringCapture(false);
	SetInputMode(Mode);
}

void ARTSController::PlayerTick(float DeltaTime)
{
	Super::PlayerTick(DeltaTime);

	UpdateCamera(DeltaTime);

	if (WasInputKeyJustPressed(EKeys::Q))
	{
		if (ARTSGameMode* GM = GetWorld()->GetAuthGameMode<ARTSGameMode>())
		{
			GM->TryTrain(0);
		}
	}

	float MX = 0.f, MY = 0.f;
	GetMousePosition(MX, MY);
	const FVector2D Mouse(MX, MY);

	if (WasInputKeyJustPressed(EKeys::LeftMouseButton))
	{
		bDragging = true;
		DragStart = Mouse;
	}
	else if (bDragging && !IsInputKeyDown(EKeys::LeftMouseButton))
	{
		bDragging = false;
		if (FVector2D::Distance(DragStart, Mouse) < 8.f)
		{
			ClickSelect();
		}
		else
		{
			BoxSelect(DragStart, Mouse);
		}
	}

	if (WasInputKeyJustPressed(EKeys::RightMouseButton))
	{
		IssueOrder();
	}
}

void ARTSController::UpdateCamera(float DeltaTime)
{
	ARTSCameraPawn* Cam = Cast<ARTSCameraPawn>(GetPawn());
	if (!Cam)
	{
		return;
	}

	FVector2D Dir = FVector2D::ZeroVector;
	if (IsInputKeyDown(EKeys::W) || IsInputKeyDown(EKeys::Up)) Dir.X += 1.f;
	if (IsInputKeyDown(EKeys::S) || IsInputKeyDown(EKeys::Down)) Dir.X -= 1.f;
	if (IsInputKeyDown(EKeys::D) || IsInputKeyDown(EKeys::Right)) Dir.Y += 1.f;
	if (IsInputKeyDown(EKeys::A) || IsInputKeyDown(EKeys::Left)) Dir.Y -= 1.f;

	float MX = 0.f, MY = 0.f;
	int32 SX = 0, SY = 0;
	if (GetMousePosition(MX, MY))
	{
		GetViewportSize(SX, SY);
		constexpr float Edge = 8.f;
		if (MY <= Edge) Dir.X += 1.f;
		if (SY > 0 && MY >= SY - Edge) Dir.X -= 1.f;
		if (SX > 0 && MX >= SX - Edge) Dir.Y += 1.f;
		if (MX <= Edge) Dir.Y -= 1.f;
	}

	const float Speed = 2500.f * (Cam->Arm->TargetArmLength / 2500.f);
	Cam->AddActorWorldOffset(FVector(Dir.X, Dir.Y, 0.f) * Speed * DeltaTime);

	float Zoom = Cam->Arm->TargetArmLength;
	if (WasInputKeyJustPressed(EKeys::MouseScrollUp)) Zoom -= 300.f;
	if (WasInputKeyJustPressed(EKeys::MouseScrollDown)) Zoom += 300.f;
	Cam->Arm->TargetArmLength = FMath::Clamp(Zoom, 800.f, 6000.f);
}

void ARTSController::ClearSelection()
{
	for (const TWeakObjectPtr<ARTSUnit>& U : Selected)
	{
		if (U.IsValid())
		{
			U->bSelected = false;
		}
	}
	Selected.Reset();
}

void ARTSController::BoxSelect(FVector2D A, FVector2D B)
{
	ClearSelection();
	const FVector2D Min(FMath::Min(A.X, B.X), FMath::Min(A.Y, B.Y));
	const FVector2D Max(FMath::Max(A.X, B.X), FMath::Max(A.Y, B.Y));
	for (TActorIterator<ARTSUnit> It(GetWorld()); It; ++It)
	{
		ARTSUnit* U = *It;
		FVector2D P;
		if (U->Team == 0 && ProjectWorldLocationToScreen(U->GetActorLocation(), P) &&
			P.X >= Min.X && P.X <= Max.X && P.Y >= Min.Y && P.Y <= Max.Y)
		{
			U->bSelected = true;
			Selected.Add(U);
		}
	}
}

void ARTSController::ClickSelect()
{
	ClearSelection();
	FHitResult Hit;
	if (GetHitResultUnderCursor(ECC_Visibility, false, Hit))
	{
		if (ARTSUnit* U = Cast<ARTSUnit>(Hit.GetActor()))
		{
			if (U->Team == 0)
			{
				U->bSelected = true;
				Selected.Add(U);
			}
		}
	}
}

void ARTSController::IssueOrder()
{
	FHitResult Hit;
	if (!GetHitResultUnderCursor(ECC_Visibility, false, Hit))
	{
		return;
	}
	ARTSEntity* Enemy = Cast<ARTSEntity>(Hit.GetActor());
	if (Enemy && Enemy->Team == 0)
	{
		Enemy = nullptr;
	}

	int32 Index = 0;
	for (const TWeakObjectPtr<ARTSUnit>& U : Selected)
	{
		if (!U.IsValid())
		{
			continue;
		}
		if (Enemy)
		{
			U->OrderAttack(Enemy);
		}
		else
		{
			const FVector Offset((Index / 5) * 90.f, ((Index % 5) - 2) * 90.f, 0.f);
			U->OrderMove(Hit.ImpactPoint + Offset);
		}
		++Index;
	}
}
