#include "RTSHUD.h"
#include "RTSController.h"
#include "RTSGameMode.h"
#include "Engine/Canvas.h"

void ARTSHUD::DrawHUD()
{
	Super::DrawHUD();

	if (ARTSController* PC = Cast<ARTSController>(GetOwningPlayerController()))
	{
		if (PC->bDragging)
		{
			float MX = 0.f, MY = 0.f;
			PC->GetMousePosition(MX, MY);
			const float X = FMath::Min((float)PC->DragStart.X, MX);
			const float Y = FMath::Min((float)PC->DragStart.Y, MY);
			const float W = FMath::Abs((float)PC->DragStart.X - MX);
			const float H = FMath::Abs((float)PC->DragStart.Y - MY);
			DrawRect(FLinearColor(0.f, 1.f, 0.f, 0.15f), X, Y, W, H);
			DrawLine(X, Y, X + W, Y, FLinearColor::Green);
			DrawLine(X, Y + H, X + W, Y + H, FLinearColor::Green);
			DrawLine(X, Y, X, Y + H, FLinearColor::Green);
			DrawLine(X + W, Y, X + W, Y + H, FLinearColor::Green);
		}
	}

	if (ARTSGameMode* GM = GetWorld()->GetAuthGameMode<ARTSGameMode>())
	{
		DrawText(FString::Printf(TEXT("Credits: %d    [Q] Train soldier (%d)    LMB select    RMB move/attack    WASD pan    Wheel zoom"),
			(int32)GM->Money[0], (int32)ARTSGameMode::UnitCost), FLinearColor::White, 20.f, 20.f, nullptr, 1.3f);
		if (!GM->Status.IsEmpty())
		{
			DrawText(GM->Status, FLinearColor::Yellow, Canvas->SizeX * 0.5f - 150.f, Canvas->SizeY * 0.4f, nullptr, 4.f);
		}
	}
}
