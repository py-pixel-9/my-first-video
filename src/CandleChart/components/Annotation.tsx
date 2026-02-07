import React from "react";
import { spring, useCurrentFrame, useVideoConfig } from "remotion";
import type { AnnotationData, ScaleContext, ThemeConfig } from "../types";

const TextAnnotation: React.FC<{
  annotation: AnnotationData;
  x: number;
  y: number;
  progress: number;
  theme: ThemeConfig;
}> = ({ annotation, x, y, progress, theme }) => {
  const color = annotation.color ?? theme.annotationColor;
  const fontSize = annotation.fontSize ?? 24;

  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        transform: `translate(-50%, -120%) scale(${progress})`,
        transformOrigin: "center bottom",
        color,
        fontSize,
        fontFamily: theme.fontFamily,
        fontWeight: "bold",
        whiteSpace: "nowrap",
        textShadow: "0 0 10px rgba(0,0,0,0.8), 0 2px 4px rgba(0,0,0,0.6)",
        opacity: progress,
      }}
    >
      {annotation.text}
    </div>
  );
};

const ArrowAnnotation: React.FC<{
  annotation: AnnotationData;
  x: number;
  y: number;
  progress: number;
  theme: ThemeConfig;
}> = ({ annotation, x, y, progress, theme }) => {
  const color = annotation.color ?? theme.annotationColor;
  const length = annotation.arrowLength ?? 40;
  const dir = annotation.arrowDirection ?? "up";

  const dx = dir === "left" ? -length : dir === "right" ? length : 0;
  const dy = dir === "up" ? -length : dir === "down" ? length : 0;

  const tipX = x;
  const tipY = y;
  const tailX = x - dx;
  const tailY = y - dy;

  const headSize = 8;
  const angle = Math.atan2(dy, dx);
  const head1X = tipX - headSize * Math.cos(angle - 0.5);
  const head1Y = tipY - headSize * Math.sin(angle - 0.5);
  const head2X = tipX - headSize * Math.cos(angle + 0.5);
  const head2Y = tipY - headSize * Math.sin(angle + 0.5);

  const lineLen = Math.sqrt(dx * dx + dy * dy);

  return (
    <g opacity={progress}>
      <line
        x1={tailX}
        y1={tailY}
        x2={tipX}
        y2={tipY}
        stroke={color}
        strokeWidth={2}
        strokeDasharray={lineLen}
        strokeDashoffset={lineLen * (1 - progress)}
        strokeLinecap="round"
      />
      <polygon
        points={`${tipX},${tipY} ${head1X},${head1Y} ${head2X},${head2Y}`}
        fill={color}
        opacity={progress}
      />
    </g>
  );
};

const CircleAnnotation: React.FC<{
  annotation: AnnotationData;
  x: number;
  y: number;
  progress: number;
  theme: ThemeConfig;
  frame: number;
}> = ({ annotation, x, y, progress, theme, frame }) => {
  const color = annotation.color ?? theme.annotationColor;
  const baseRadius = annotation.radius ?? 20;
  const pulse = 1 + Math.sin(frame * 0.15) * 0.05;
  const r = baseRadius * progress * pulse;

  return (
    <circle
      cx={x}
      cy={y}
      r={r}
      fill="none"
      stroke={color}
      strokeWidth={2}
      opacity={progress * 0.8}
    />
  );
};

export const Annotation: React.FC<{
  annotation: AnnotationData;
  scale: ScaleContext;
  theme: ThemeConfig;
  appearFrame: number;
}> = ({ annotation, scale, theme, appearFrame }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const localFrame = frame - appearFrame;
  if (localFrame < 0) return null;

  const progress = spring({
    frame: localFrame,
    fps,
    config: { damping: 18, mass: 0.5, stiffness: 100 },
  });

  const x = scale.xScale(annotation.index);
  const y = scale.yScale(annotation.price);

  if (annotation.type === "text") {
    return (
      <TextAnnotation
        annotation={annotation}
        x={x}
        y={y}
        progress={progress}
        theme={theme}
      />
    );
  }

  return null;
};

export const SvgAnnotation: React.FC<{
  annotation: AnnotationData;
  scale: ScaleContext;
  theme: ThemeConfig;
  appearFrame: number;
}> = ({ annotation, scale, theme, appearFrame }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const localFrame = frame - appearFrame;
  if (localFrame < 0) return null;

  const progress = spring({
    frame: localFrame,
    fps,
    config: { damping: 18, mass: 0.5, stiffness: 100 },
  });

  const x = scale.xScale(annotation.index);
  const y = scale.yScale(annotation.price);

  if (annotation.type === "arrow") {
    return (
      <ArrowAnnotation
        annotation={annotation}
        x={x}
        y={y}
        progress={progress}
        theme={theme}
      />
    );
  }

  if (annotation.type === "circle") {
    return (
      <CircleAnnotation
        annotation={annotation}
        x={x}
        y={y}
        progress={progress}
        theme={theme}
        frame={frame}
      />
    );
  }

  return null;
};
