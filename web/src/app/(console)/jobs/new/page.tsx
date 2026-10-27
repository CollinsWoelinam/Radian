import { Suspense } from "react";
import NewJobPage from "@/console/pages/NewJobPage";

export default function Page() {
  return (
    <Suspense>
      <NewJobPage />
    </Suspense>
  );
}
