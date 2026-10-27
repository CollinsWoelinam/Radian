import { Suspense } from "react";
import VehiclesPage from "@/console/pages/VehiclesPage";

export default function Page() {
  return (
    <Suspense>
      <VehiclesPage />
    </Suspense>
  );
}
