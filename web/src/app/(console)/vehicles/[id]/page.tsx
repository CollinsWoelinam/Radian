import { Suspense } from "react";
import VehiclePage from "@/console/pages/VehiclePage";

export default function Page() {
  return (
    <Suspense>
      <VehiclePage />
    </Suspense>
  );
}
