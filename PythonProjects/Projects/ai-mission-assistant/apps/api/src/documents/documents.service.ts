import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as fs from 'fs';
import * as path from 'path';
import { PrismaService } from '../prisma/prisma.service';
import { IngestionService } from '../ingestion/ingestion.service';

@Injectable()
export class DocumentsService {
  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
    private ingestion: IngestionService,
  ) {}

  async upload(userId: string, file: Express.Multer.File) {
    if (file.mimetype !== 'application/pdf') {
      // Clean up uploaded file if wrong type
      fs.unlinkSync(file.path);
      throw new BadRequestException('Only PDF files are accepted');
    }

    const document = await this.prisma.document.create({
      data: {
        userId,
        originalName: file.originalname,
        storedFilename: file.filename,
        mimeType: file.mimetype,
        fileSize: file.size,
        status: 'UPLOADED',
      },
    });

    // Kick off ingestion asynchronously — don't block the upload response
    this.ingestion.ingest(document.id, file.path).catch((err) => {
      console.error(`Ingestion failed for document ${document.id}:`, err);
    });

    return document;
  }

  async findAll(userId: string) {
    return this.prisma.document.findMany({
      where: { userId },
      select: {
        id: true,
        originalName: true,
        fileSize: true,
        status: true,
        errorMessage: true,
        createdAt: true,
        updatedAt: true,
        _count: { select: { chunks: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: string, userId: string) {
    const doc = await this.prisma.document.findUnique({ where: { id } });
    if (!doc) throw new NotFoundException('Document not found');
    if (doc.userId !== userId) throw new ForbiddenException();
    return doc;
  }

  async remove(id: string, userId: string) {
    const doc = await this.findOne(id, userId);

    // Delete the stored file
    const uploadDir = this.config.get<string>('upload.uploadDir')!;
    const filePath = path.join(uploadDir, doc.storedFilename);
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);

    // Cascade deletes chunks via Prisma schema relation
    await this.prisma.document.delete({ where: { id } });
    return { message: 'Document deleted' };
  }
}
